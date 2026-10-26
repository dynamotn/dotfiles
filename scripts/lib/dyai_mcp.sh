# @file dyai_mcp.sh
# @brief Serve dyai's per-project preset commands to agents as an MCP server
# @description `dyai mcp` speaks MCP over stdio (newline-delimited JSON-RPC)
# so an agent can list the registry presets and opt the current project into
# one, or out of one, and drive a crew of headless agents (`crew_*`), without
# a shell round trip. Each tool runs the matching
# `dyai::*` function in a subshell with stdin closed, so a `die` ends only that
# call and nothing it prints reaches the protocol stream. Sourced (not
# executed); the caller sources dybatpho first and owns strict mode.
# shellcheck shell=bash

# The MCP revision answered when a client does not name one.
DYAI_MCP_PROTOCOL="2025-06-18"

# Written by hand: dybatpho::agent_mcp drops positional arguments such as
# PRESET from the generated input schema. A jq program, so long descriptions
# can be split over lines.
DYAI_MCP_TOOLS_JQ='
def id_arg: {type: "object", required: ["id"], additionalProperties: false,
  properties: {id: {type: "string", description: "Task id, as crew_run or crew_tasks printed it"}}};
def preset_arg: {type: "object", required: ["preset"], additionalProperties: false,
  properties: {preset: {type: "string", description: "Preset name, as listed by ls"}}};
[{name: "ls",
  description: ("List the dyai global baseline, every registry preset (languages, infra,"
    + " presets), and the presets the current project already uses. Call this before"
    + " use or rm to get valid preset names."),
  inputSchema: {type: "object", properties: {}, additionalProperties: false}},
 {name: "use",
  description: ("Opt the current project (the git repository of the working directory)"
    + " into a dyai registry preset, installing its skills, subagents, MCP servers and"
    + " plugins for every agent. Use it when the task needs a language, infra or role"
    + " preset the project does not use yet. New MCP servers and plugins load on the"
    + " next agent session."),
  inputSchema: preset_arg},
 {name: "rm",
  description: ("Remove a dyai preset from the current project and prune the files only"
    + " it installed."),
  inputSchema: preset_arg},
 {name: "crew_run",
  description: ("Hand a task to a headless agent CLI (claude, codex, gemini, opencode, copilot)"
    + " in its own git worktree of the current repository. Returns the task id at once; the"
    + " task runs in the background, so poll crew_tasks. agent defaults to auto (the first"
    + " configured agent that is installed and not rate limited)."),
  inputSchema: {type: "object", required: ["prompt"], additionalProperties: false, properties: {
    prompt: {type: "string", description: "The task, as you would write it for a person"},
    agent: {type: "string", enum: ["auto", "claude", "codex", "gemini", "opencode", "copilot"]},
    plan: {type: "string", description: "A plan file inside the repository the agent must follow"}}}},
 {name: "crew_tasks",
  description: "List the crew tasks of the current repository: id, status, agent, summary.",
  inputSchema: {type: "object", properties: {}, additionalProperties: false}},
 {name: "crew_review",
  description: ("Have another agent review a done task read-only; the verdict (pass, fail,"
    + " unknown) lands in crew_tasks. Runs in the background."),
  inputSchema: (id_arg | .properties.by = {type: "string",
    enum: ["claude", "codex", "gemini", "opencode", "copilot"]})},
 {name: "crew_fix",
  description: "After a fail verdict, run the writer again on the findings of the review. Runs in the background.",
  inputSchema: id_arg},
 {name: "crew_merge",
  description: ("Merge a done task with a pass verdict into the current branch (never main or"
    + " master), behind the configured fences and gate."),
  inputSchema: id_arg},
 {name: "crew_drop",
  description: "Remove the worktree of a task; its branch goes only when merged.",
  inputSchema: id_arg},
 {name: "crew_logs",
  description: "The last lines of the agent output of a task.",
  inputSchema: (id_arg | .properties.lines = {type: "integer", minimum: 1, maximum: 500})}]
'

#######################################
# @description Print one JSON-RPC message on its own line
# @arg $1 string Request id, as JSON
# @arg $2 string `result` or `error`
# @arg $3 string The member's value, as JSON
# @stdout The message
#######################################
function dyai_mcp::send {
  local id key value
  dybatpho::expect_args id key value -- "$@"
  jq -cn --argjson id "${id}" --arg key "${key}" --argjson value "${value}" \
    '{jsonrpc: "2.0", id: $id, ($key): $value}'
}

#######################################
# @description Run one tool and print its MCP `tools/call` result
# @arg $1 string Tool name
# @arg $2 string Tool arguments, as a JSON object
# @stdout The result object; a failed command is `isError: true`, not a protocol error
#######################################
function dyai_mcp::call {
  local name arguments
  dybatpho::expect_args name arguments -- "$@"
  local output failed=false
  local -a cmd=()
  # Every value is checked before it reaches a command line; a bad one is a
  # tool error and runs nothing.
  # shellcheck disable=SC2310 # a refusal is a plain yes/no; its text lands in output
  if ! __dyai_mcp_command "${name}" "${arguments}" cmd output; then
    failed=true
  else
    # shellcheck disable=SC2310 # the subshell's own exit code is the result
    if ! output="$( (${cmd[@]+"${cmd[@]}"}) < /dev/null 2>&1)"; then
      failed=true
    elif [[ "${name}" == use || "${name}" == rm ]]; then
      output+=$'\nNew MCP servers and plugins load on the next agent session.'
    fi
  fi
  jq -cn --arg text "${output}" --argjson failed "${failed}" \
    '{content: [{type: "text", text: $text}], isError: $failed}'
}

#######################################
# @description Turn one tool call into the command line it runs, after checking its arguments
# @arg $1 string Tool name
# @arg $2 string Tool arguments, as a JSON object
# @arg $3 string Name of the array to fill
# @arg $4 string Name of the variable that gets why the call is refused
# @exitcode 1 Refused
#######################################
function __dyai_mcp_command {
  local __dyai_mcp_name __dyai_mcp_args __dyai_mcp_outvar __dyai_mcp_whyvar
  dybatpho::expect_args __dyai_mcp_name __dyai_mcp_args __dyai_mcp_outvar __dyai_mcp_whyvar -- "$@"
  local -n __dyai_mcp_cmd="${__dyai_mcp_outvar}" __dyai_mcp_why="${__dyai_mcp_whyvar}"
  local __dyai_mcp_preset __dyai_mcp_id __dyai_mcp_agent __dyai_mcp_by __dyai_mcp_plan
  local __dyai_mcp_prompt __dyai_mcp_lines
  __dyai_mcp_preset="$(jq -r '.preset // empty | strings' <<< "${__dyai_mcp_args}")"
  __dyai_mcp_id="$(jq -r '.id // empty | strings' <<< "${__dyai_mcp_args}")"
  case "${__dyai_mcp_name}" in
    crew_review | crew_fix | crew_merge | crew_drop | crew_logs)
      if [[ ! "${__dyai_mcp_id}" =~ ^[0-9]{8}-[0-9]{6}-[a-z]+-[0-9a-f]{4}$ ]]; then
        printf -v __dyai_mcp_why 'invalid task id: %s' "${__dyai_mcp_id:-<missing>}"
        return 1
      fi
      ;;
    *) ;;
  esac
  case "${__dyai_mcp_name}" in
    ls) __dyai_mcp_cmd=(dyai::ls) ;;
    use | rm)
      # The name is spliced into jq filters by dyai::resolve_preset; only a
      # plain preset name may reach it.
      if [[ ! "${__dyai_mcp_preset}" =~ ^[A-Za-z0-9._-]+$ ]]; then
        printf -v __dyai_mcp_why 'invalid preset name: %s' "${__dyai_mcp_preset:-<missing>}"
        return 1
      fi
      __dyai_mcp_cmd=("dyai::${__dyai_mcp_name}" "${__dyai_mcp_preset}")
      ;;
    crew_run)
      __dyai_mcp_prompt="$(jq -r '.prompt // empty | strings' <<< "${__dyai_mcp_args}")"
      __dyai_mcp_agent="$(jq -r '.agent // "auto" | strings' <<< "${__dyai_mcp_args}")"
      __dyai_mcp_plan="$(jq -r '.plan // empty | strings' <<< "${__dyai_mcp_args}")"
      if [[ -z "${__dyai_mcp_prompt}" ]]; then
        __dyai_mcp_why='crew_run needs a prompt'
        return 1
      fi
      if [[ " auto claude codex gemini opencode copilot " != *" ${__dyai_mcp_agent} "* ]]; then
        printf -v __dyai_mcp_why 'unknown agent: %s' "${__dyai_mcp_agent}"
        return 1
      fi
      if [[ -n "${__dyai_mcp_plan}" ]]; then
        local __dyai_mcp_root __dyai_mcp_real
        __dyai_mcp_root="$(git rev-parse --show-toplevel 2> /dev/null)" || __dyai_mcp_root=""
        __dyai_mcp_real="$(realpath -e -- "${__dyai_mcp_plan}" 2> /dev/null)" || __dyai_mcp_real=""
        if [[ -z "${__dyai_mcp_root}" || -z "${__dyai_mcp_real}" ||
          "${__dyai_mcp_real}" != "${__dyai_mcp_root}"/* ]]; then
          printf -v __dyai_mcp_why 'plan must be a file inside the repository: %s' "${__dyai_mcp_plan}"
          return 1
        fi
        __dyai_mcp_plan="${__dyai_mcp_real}"
      fi
      __dyai_mcp_cmd=(dyai_crew::run "${__dyai_mcp_agent}" "${__dyai_mcp_prompt}" "${__dyai_mcp_plan}" detach)
      ;;
    crew_tasks) __dyai_mcp_cmd=(dyai_crew::list) ;;
    crew_review)
      __dyai_mcp_by="$(jq -r '.by // empty | strings' <<< "${__dyai_mcp_args}")"
      if [[ -n "${__dyai_mcp_by}" && " claude codex gemini opencode copilot " != *" ${__dyai_mcp_by} "* ]]; then
        printf -v __dyai_mcp_why 'unknown agent: %s' "${__dyai_mcp_by}"
        return 1
      fi
      __dyai_mcp_cmd=(dyai_crew::review "${__dyai_mcp_id}" "${__dyai_mcp_by}" detach)
      ;;
    crew_fix) __dyai_mcp_cmd=(dyai_crew::fix "${__dyai_mcp_id}" detach) ;;
    crew_merge) __dyai_mcp_cmd=(dyai_crew::merge "${__dyai_mcp_id}") ;;
    crew_drop) __dyai_mcp_cmd=(dyai_crew::drop "${__dyai_mcp_id}") ;;
    crew_logs)
      __dyai_mcp_lines="$(jq -r '.lines // 50 | numbers | floor | if . < 1 then 1 elif . > 500 then 500 else . end' \
        <<< "${__dyai_mcp_args}" 2> /dev/null)" || __dyai_mcp_lines=50
      [[ -n "${__dyai_mcp_lines}" ]] || __dyai_mcp_lines=50
      __dyai_mcp_cmd=(__dyai_mcp_logs "${__dyai_mcp_id}" "${__dyai_mcp_lines}")
      ;;
    *)
      printf -v __dyai_mcp_why 'unknown tool: %s' "${__dyai_mcp_name}"
      return 1
      ;;
  esac
}

#######################################
# @description Print the last lines of a crew task's agent output
# @arg $1 string Task id
# @arg $2 string Line count
#######################################
function __dyai_mcp_logs {
  local id lines
  dybatpho::expect_args id lines -- "$@"
  local dir
  dir="$(dyai_crew::state_dir)" || return 1
  dybatpho::is file "${dir}/${id}.out" || dybatpho::die "no log for ${id}"
  tail -n "${lines}" -- "${dir}/${id}.out"
}

#######################################
# @description Answer one JSON-RPC message; notifications get no reply
# @arg $1 string The raw message line
# @stdout The reply, if any
#######################################
function dyai_mcp::handle {
  local line
  dybatpho::expect_args line -- "$@"
  local fields method id params
  # Joined on the unit separator, not @tsv: tab is IFS whitespace, so an empty
  # id would collapse, and @tsv doubles the backslashes inside the JSON.
  if ! fields="$(jq -r '[(.method // "" | tostring),
      (if has("id") then .id | tojson else "" end),
      (.params // {} | tojson)] | join("\u001f")' <<< "${line}" 2> /dev/null)"; then
    dyai_mcp::send null error '{"code": -32700, "message": "Parse error"}'
    return 0
  fi
  IFS=$'\x1f' read -r method id params <<< "${fields}"
  [[ -n "${id}" ]] || return 0
  local key=result value tool arguments
  case "${method}" in
    initialize)
      value="$(jq -cn --argjson p "${params}" --arg v "${DYAI_MCP_PROTOCOL}" \
        '{protocolVersion: ($p.protocolVersion // $v), capabilities: {tools: {}},
          serverInfo: {name: "dyai", version: "1.0.0"}}')"
      ;;
    ping) value='{}' ;;
    tools/list) value="$(jq -cn "${DYAI_MCP_TOOLS_JQ}"' | {tools: .}')" ;;
    tools/call)
      tool="$(jq -r '.name // "" | tostring' <<< "${params}")"
      arguments="$(jq -c '.arguments // {}' <<< "${params}")"
      value="$(dyai_mcp::call "${tool}" "${arguments}")"
      ;;
    *)
      key=error
      value="$(jq -cn --arg m "${method}" '{code: -32601, message: ("Method not found: " + $m)}')"
      ;;
  esac
  dyai_mcp::send "${id}" "${key}" "${value}"
}

#######################################
# @description Serve MCP on stdin/stdout until the client closes stdin
# @noargs
#######################################
function dyai_mcp::serve {
  export NO_COLOR=1
  local line
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -n "${line//[[:space:]]/}" ]] || continue
    dyai_mcp::handle "${line}"
  done
}
