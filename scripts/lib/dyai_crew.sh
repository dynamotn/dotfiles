# @file dyai_crew.sh
# @brief Run tasks on headless agent CLIs in their own worktrees, review and merge them
# @description `dyai run`, `review`, `fix`, `merge` and friends. Each agent is
# its real CLI in headless mode, so it keeps the skills, MCP servers and policy
# `dyai install` gave it; dyai never calls a provider API and holds no model.
# State is one append-only JSONL file per repository, written under `flock`.
# Prompts never travel as argv (a review prompt carries a diff, and Linux caps
# one argument at 128 KiB): they reach the agent on stdin or as a file.
# Sourced (not executed) after dyai.sh; the caller sources dybatpho first.
# docs/superpowers/plans/2026-10-26-dyai-crew.md is the design.
# shellcheck shell=bash

# Error text that means "come back later" or "this agent cannot run here".
DYAI_CREW_RATE_RE='rate.?limit|usage limit|quota|\b429\b|resource_exhausted'
DYAI_CREW_BLOCKED_RE='\b401\b|unauthori[sz]ed|not authenticated|authentication page'
DYAI_CREW_BLOCKED_RE+='|api key is missing|ProviderAuthError|login required'
# dyshellint disable=SC2034 set by dyai_crew::cmd, read by its callers
DYAI_CREW_STDIN=/dev/null

#######################################
# @description Read one global.crew value from the dyai config
# @arg $1 string yq path, e.g. '.global.crew.timeout'
# @arg $2 string Value printed when the key is unset or the config is missing
# @stdout The value (a scalar as text, an object or array as compact JSON)
#######################################
function dyai_crew::conf {
  local expr default
  dybatpho::expect_args expr default -- "$@"
  local cfg="${CONFIG_FILE:-${HOME}/.config/dyai/config.yaml}" value=""
  if dybatpho::is file "${cfg}"; then
    # Not `// default`: that would also replace a configured `false`.
    value="$(yq -o=json -I=0 "${expr}" "${cfg}" 2> /dev/null)" || value=""
  fi
  if [[ -z "${value}" || "${value}" == null ]]; then
    printf '%s' "${default}"
  else
    jq -r 'if type == "string" then . else tojson end' <<< "${value}"
  fi
}

#######################################
# @description Fill an array with the headless command line of one agent
# @arg $1 string Agent: claude, codex, gemini, opencode or copilot
# @arg $2 string Mode: rw (may edit) or ro (read-only)
# @arg $3 string Prompt file
# @arg $4 string Name of the array to fill
# @arg $5 string Codex only: file its last message is written to
# @set DYAI_CREW_STDIN string File the caller redirects into the command's stdin
#######################################
function dyai_crew::cmd {
  local __dyai_crew_cmd_agent __dyai_crew_cmd_mode __dyai_crew_cmd_prompt __dyai_crew_cmd_outvar
  dybatpho::expect_args __dyai_crew_cmd_agent __dyai_crew_cmd_mode \
    __dyai_crew_cmd_prompt __dyai_crew_cmd_outvar -- "$@"
  local __dyai_crew_cmd_last="${5:-}"
  local -n __dyai_crew_cmd="${__dyai_crew_cmd_outvar}"
  [[ "${__dyai_crew_cmd_mode}" == rw || "${__dyai_crew_cmd_mode}" == ro ]] \
    || dybatpho::die "unknown mode: ${__dyai_crew_cmd_mode}"
  local __dyai_crew_cmd_model
  __dyai_crew_cmd_model="$(dyai_crew::conf ".global.crew.model.${__dyai_crew_cmd_agent}" "")"
  DYAI_CREW_STDIN="${__dyai_crew_cmd_prompt}"
  case "${__dyai_crew_cmd_agent}" in
    claude)
      __dyai_crew_cmd=(claude -p --output-format stream-json --verbose --permission-mode)
      if [[ "${__dyai_crew_cmd_mode}" == ro ]]; then __dyai_crew_cmd+=(plan); else __dyai_crew_cmd+=(acceptEdits); fi
      __dyai_crew_cmd+=(--no-session-persistence)
      [[ -z "${__dyai_crew_cmd_model}" ]] || __dyai_crew_cmd+=(--model "${__dyai_crew_cmd_model}")
      ;;
    codex)
      [[ -n "${__dyai_crew_cmd_last}" ]] || dybatpho::die "codex needs a file for its last message"
      __dyai_crew_cmd=(codex exec --sandbox)
      if [[ "${__dyai_crew_cmd_mode}" == ro ]]; then
        __dyai_crew_cmd+=(read-only)
      else
        __dyai_crew_cmd+=(workspace-write)
      fi
      __dyai_crew_cmd+=(--ephemeral --json -o "${__dyai_crew_cmd_last}")
      [[ -z "${__dyai_crew_cmd_model}" ]] || __dyai_crew_cmd+=(-m "${__dyai_crew_cmd_model}")
      # `-` reads the prompt from stdin; it stays the last argument.
      __dyai_crew_cmd+=(-)
      ;;
    gemini)
      __dyai_crew_cmd=(gemini --prompt "Follow the task given on stdin." --output-format stream-json --approval-mode)
      if [[ "${__dyai_crew_cmd_mode}" == ro ]]; then __dyai_crew_cmd+=(plan); else __dyai_crew_cmd+=(auto_edit); fi
      __dyai_crew_cmd+=(--skip-trust)
      [[ -z "${__dyai_crew_cmd_model}" ]] || __dyai_crew_cmd+=(-m "${__dyai_crew_cmd_model}")
      ;;
    opencode)
      # opencode run reads no stdin; the prompt goes in as an attached file.
      __dyai_crew_cmd=(opencode run --format json -f "${__dyai_crew_cmd_prompt}" "Follow the attached task file.")
      [[ "${__dyai_crew_cmd_mode}" == rw ]] || __dyai_crew_cmd+=(--agent plan)
      [[ -z "${__dyai_crew_cmd_model}" ]] || __dyai_crew_cmd+=(-m "${__dyai_crew_cmd_model}")
      # dyshellint disable=SC2034 read by the caller, like the assignment above
      DYAI_CREW_STDIN=/dev/null
      ;;
    copilot)
      # Piped stdin is the prompt only when -p is absent.
      __dyai_crew_cmd=(copilot --silent --output-format json --allow-all-tools --deny-tool "shell(git push)")
      [[ "${__dyai_crew_cmd_mode}" == rw ]] || __dyai_crew_cmd+=(--deny-tool shell --deny-tool write)
      [[ -z "${__dyai_crew_cmd_model}" ]] || __dyai_crew_cmd+=(--model "${__dyai_crew_cmd_model}")
      ;;
    *) dybatpho::die "unknown agent: ${__dyai_crew_cmd_agent}" ;;
  esac
}

#######################################
# @description Print an agent's final answer text from its headless output
# @arg $1 string Agent
# @arg $2 string File holding the agent's stdout
# @arg $3 string Codex only: its last-message file
# @stdout The answer text
#######################################
function dyai_crew::text {
  local agent out
  dybatpho::expect_args agent out -- "$@"
  local last="${3:-}" filter
  case "${agent}" in
    codex)
      [[ -n "${last}" ]] && dybatpho::is file "${last}" && cat -- "${last}"
      return 0
      ;;
    claude) filter='map(select(.type == "result")) | last | .result // empty' ;;
    copilot) filter='map(select(.type == "assistant.message")) | last | .data.content // empty' ;;
    gemini) filter='map(select(.type == "message" and .role == "assistant") | .content) | join("")' ;;
    opencode) filter='map(select(.type == "text") | .part.text) | join("\n")' ;;
    *) dybatpho::die "unknown agent: ${agent}" ;;
  esac
  # Lines that are not JSON (banners, prompts) are skipped, not fatal.
  jq -rRn "[inputs | fromjson? | objects] | ${filter}" "${out}" 2> /dev/null || true
}

#######################################
# @description Classify a failed agent run from its error output
# @arg $1 string Agent
# @arg $2 string File holding the agent's stdout
# @arg $3 string File holding the agent's stderr
# @stdout `rate_limited`, `blocked`, or nothing
#######################################
function dyai_crew::failure {
  local agent out err
  dybatpho::expect_args agent out err -- "$@"
  local text=""
  text="$(tail -n 50 -- "${err}" 2> /dev/null || true)"
  # From stdout only what is error text: lines that are not JSON (an auth
  # prompt), a failed claude result, and error events. The answer itself
  # is left out, so a task about quotas does not read as a rate limit.
  text+=$'\n'"$(jq -rRn '
    inputs | . as $line | (fromjson? // {raw: $line})
    | if (.raw | type) == "string" then .raw
      elif .type == "result" and .is_error == true then .result
      elif .type == "error" then [.error.name?, .error.data.message?, .message?, .error.message?]
        | map(select(type == "string")) | join(" ")
      else empty end' "${out}" 2> /dev/null | tail -n 50 || true)"
  if grep -Eiq -- "${DYAI_CREW_RATE_RE}" <<< "${text}"; then
    printf 'rate_limited\n'
  elif grep -Eiq -- "${DYAI_CREW_BLOCKED_RE}" <<< "${text}"; then
    printf 'blocked\n'
  fi
  return 0
}

#######################################
# @description Print the root of the main checkout, even from a linked worktree
# @noargs
# @stdout The absolute path
#######################################
function dyai_crew::main_checkout {
  local common
  common="$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null)" \
    || dybatpho::die "dyai crew must run inside a git repository"
  dirname -- "${common}"
}

#######################################
# @description Print the crew state directory, creating it and personal-ignoring it
# @noargs
# @stdout `<main checkout>/.dyai/crew`
#######################################
function dyai_crew::state_dir {
  local root dir exclude
  root="$(dyai_crew::main_checkout)" || return 1
  dir="${root}/.dyai/crew"
  dybatpho::ensure_dir "${dir}" > /dev/null
  # shellcheck disable=SC2310 # outside a normal checkout there is no personal ignore
  if exclude="$(dyai::git_exclude "${root}")"; then
    dyai::exclude_add "${exclude}" '/.dyai/'
  fi
  printf '%s\n' "${dir}"
}

#######################################
# @description Print the last recorded line of one task from a log file
# @arg $1 string tasks.jsonl
# @arg $2 string Task id
# @stdout The line, or nothing
#######################################
function __dyai_crew_last {
  local log id
  dybatpho::expect_args log id -- "$@"
  dybatpho::is file "${log}" || return 0
  local lines
  lines="$(jq -c --arg id "${id}" 'select(.id == $id)' "${log}" 2> /dev/null)" || return 0
  [[ -z "${lines}" ]] || printf '%s\n' "${lines##*$'\n'}"
}

#######################################
# @description Merge new fields over a task's last state and append the result
# @arg $1 string Task id
# @arg $2 string Fields to set, as a JSON object
#######################################
function dyai_crew::record {
  local id json
  dybatpho::expect_args id json -- "$@"
  local dir log old new ts before after
  dir="$(dyai_crew::state_dir)"
  log="${dir}/tasks.jsonl"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  {
    # Read and append under one lock: reading outside it would let two
    # writers start from the same state and drop each other's fields.
    flock 9
    old="$(__dyai_crew_last "${log}" "${id}")"
    new="$(jq -cn --argjson o "${old:-null}" --argjson n "${json}" --arg id "${id}" --arg ts "${ts}" \
      '($o // {}) * $n + {id: $id, ts: $ts}')" || dybatpho::die "record ${id}: fields are not a JSON object"
    printf '%s\n' "${new}" >> "${log}"
  } 9>> "${dir}/tasks.lock"
  before="$(jq -r '.status // ""' <<< "${old:-null}")"
  after="$(jq -r '.status // ""' <<< "${new}")"
  [[ "${before}" != "${after}" ]] || return 0
  local hook
  hook="$(dyai_crew::conf '.global.crew.hooks.on_status' "")"
  [[ -n "${hook}" ]] || return 0
  if ! DYAI_TASK_ID="${id}" DYAI_STATUS="${after}" bash -c "${hook}" < /dev/null; then
    dybatpho::warn "on_status hook failed for ${id} (${after})"
  fi
  return 0
}

#######################################
# @description Print a task's last state
# @arg $1 string Task id
# @stdout The state as JSON
# @exitcode 1 No such task
#######################################
function dyai_crew::get {
  local id
  dybatpho::expect_args id -- "$@"
  local line dir
  dir="$(dyai_crew::state_dir)"
  line="$(__dyai_crew_last "${dir}/tasks.jsonl" "${id}")"
  [[ -n "${line}" ]] || return 1
  printf '%s\n' "${line}"
}

#######################################
# @description Tell whether a recorded process is still the one that was recorded
# @arg $1 string Process id
# @arg $2 string Its start time as `ps -o lstart=` printed it
# @exitcode 0 Alive and the same process
#######################################
function dyai_crew::alive {
  local pid start
  dybatpho::expect_args pid start -- "$@"
  [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
  kill -0 "${pid}" 2> /dev/null || return 1
  local now
  now="$(ps -o lstart= -p "${pid}" 2> /dev/null)" || return 1
  [[ "${now}" == "${start}" ]]
}

#######################################
# @description List every task's last state, oldest first
# @noargs
# @stdout `id<TAB>status<TAB>agent<TAB>summary` per task; a dead running task reads `lost`
#######################################
function dyai_crew::list {
  local dir log
  dir="$(dyai_crew::state_dir)"
  log="${dir}/tasks.jsonl"
  dybatpho::is file "${log}" || return 0
  local id status agent pid start summary
  # Joined on the unit separator, not tabs: read would collapse empty fields.
  # shellcheck disable=SC2312 # a corrupt log lists nothing rather than aborting
  while IFS=$'\x1f' read -r id status agent pid start summary; do
    if [[ "${status}" == running ]] && ! dyai_crew::alive "${pid}" "${start}"; then
      status=lost
    fi
    printf '%s\t%s\t%s\t%s\n' "${id}" "${status}" "${agent}" "${summary}"
  done < <(jq -rs '
    reduce .[] as $l ({order: [], last: {}};
      (if .last[$l.id] then . else .order += [$l.id] end) | .last[$l.id] = $l)
    | .order[] as $i | .last[$i]
    | [.id, (.status // ""), (.agent // ""), (.pid // "" | tostring), (.pid_start // ""),
       (.summary // "" | tostring | gsub("[\t\n\u001f]"; " "))]
    | join("\u001f")' "${log}" 2> /dev/null)
}
