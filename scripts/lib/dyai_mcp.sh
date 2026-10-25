# @file dyai_mcp.sh
# @brief Serve dyai's per-project preset commands to agents as an MCP server
# @description `dyai mcp` speaks MCP over stdio (newline-delimited JSON-RPC)
# so an agent can list the registry presets and opt the current project into
# one, or out of one, without a shell round trip. Each tool runs the matching
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
  inputSchema: preset_arg}]
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
  local preset output failed=false
  preset="$(jq -r '.preset // empty | strings' <<< "${arguments}")"
  case "${name}" in
    ls) ;;
    use | rm)
      # The name is spliced into jq filters by dyai::resolve_preset; only a
      # plain preset name may reach it.
      if [[ ! "${preset}" =~ ^[A-Za-z0-9._-]+$ ]]; then
        output="invalid preset name: ${preset:-<missing>}"
        failed=true
      fi
      ;;
    *)
      output="unknown tool: ${name}"
      failed=true
      ;;
  esac
  if [[ "${failed}" == false ]]; then
    # shellcheck disable=SC2310 # the subshell's own exit code is the result
    if ! output="$( (dyai::"${name}" ${preset:+"${preset}"}) < /dev/null 2>&1)"; then
      failed=true
    elif [[ "${name}" != ls ]]; then
      output+=$'\nNew MCP servers and plugins load on the next agent session.'
    fi
  fi
  jq -cn --arg text "${output}" --argjson failed "${failed}" \
    '{content: [{type: "text", text: $text}], isError: $failed}'
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
