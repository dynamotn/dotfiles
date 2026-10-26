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
# A diff above this many bytes goes to the reviewer as a file, not inline.
DYAI_CREW_INLINE_DIFF=96000
# What every worker is told on top of its task.
# shellcheck disable=SC2016 # Markdown backticks, not command substitution
DYAI_CREW_CONTRACT='
## Contract with dyai crew

- Work only inside this directory. Do not push, and do not switch or create
  branches: stay on the branch this worktree has checked out.
- When you are finished, write `.dyai-result.json` at the root of this
  directory, as one JSON object:
  `{"status": "done" | "failed" | "partial", "summary": "<one line>"}`.
  `done` means the task is complete and your changes are in the files.
- dyai commits your changes itself; you do not have to.
'

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

#######################################
# @description Print a new task id for an agent: date, time, agent, 4 hex digits
# @arg $1 string Agent
# @stdout The id
#######################################
function dyai_crew::new_id {
  local agent
  dybatpho::expect_args agent -- "$@"
  local id stamp hex
  while :; do
    stamp="$(date +%Y%m%d-%H%M%S)"
    printf -v hex '%04x' $(((RANDOM ^ $$ ^ BASHPID) & 0xffff))
    id="${stamp}-${agent}-${hex}"
    git show-ref --verify -q "refs/heads/crew/${id}" || break
  done
  printf '%s\n' "${id}"
}

#######################################
# @description Tell whether an agent is still cooling down after a rate limit or an auth failure
# @arg $1 string Agent
# @exitcode 0 Still cooling down
#######################################
function dyai_crew::cooling {
  local agent
  dybatpho::expect_args agent -- "$@"
  local dir until now
  dir="$(dyai_crew::state_dir)" || return 1
  dybatpho::is file "${dir}/cooldown/${agent}" || return 1
  until="$(< "${dir}/cooldown/${agent}")"
  now="$(date +%s)"
  [[ "${until}" =~ ^[0-9]+$ ]] && ((until > now))
}

#######################################
# @description Remove a task's worktree and branch when they hold no work
# @arg $1 string Task id
# @exitcode 0 Both are gone
# @exitcode 1 Something was kept: uncommitted files, or commits that are not merged
#######################################
function __dyai_crew_remove_worktree {
  local id
  dybatpho::expect_args id -- "$@"
  local root wt
  root="$(dyai_crew::main_checkout)" || return 1
  wt="${root}/.worktrees/crew-${id}"
  if dybatpho::is dir "${wt}"; then
    # Without --force: a worktree with changes in it is refused, not lost.
    git -C "${root}" worktree remove "${wt}" &> /dev/null || return 1
  fi
  if git -C "${root}" show-ref --verify -q "refs/heads/crew/${id}"; then
    # -d, never -D: a branch with unmerged commits stays.
    git -C "${root}" branch -q -d "crew/${id}" &> /dev/null || return 1
  fi
  return 0
}

#######################################
# @description Count the commits a task's branch holds on top of its base
# @arg $1 string Worktree
# @arg $2 string Base commit
# @arg $3 string Task id
# @stdout The count; 0 when git cannot tell
#######################################
function __dyai_crew_ahead {
  local wt base id
  dybatpho::expect_args wt base id -- "$@"
  local count
  count="$(git -C "${wt}" rev-list --count "${base}..crew/${id}" 2> /dev/null)" || count=0
  printf '%s\n' "${count}"
}

#######################################
# @description Open a crew view when global.crew.panes allows it; never fails
# @arg $@ string The arguments of dyai_zellij::open
#######################################
function __dyai_crew_pane {
  local panes
  panes="$(dyai_crew::conf '.global.crew.panes' auto)"
  [[ "${panes}" == auto ]] || return 0
  # shellcheck disable=SC2310 # no terminal to show it in is fine
  dyai_zellij::open "$@" || true
}

#######################################
# @description Run an agent command line in a worktree, in its own process group, under a time limit
# @arg $1 string Task id (exported to the agent as DYAI_CREW)
# @arg $2 string Agent
# @arg $3 string Worktree
# @arg $4 string File for stdout
# @arg $5 string File for stderr
# @arg $6 string Seconds before the agent is stopped
# @arg $7 string Name of the array holding the command line
# @arg $8 string `task`: record the pid as running and open the log pane; `review`: neither
# @exitcode The agent's exit code; 124 or 137 on a timeout
#######################################
function __dyai_crew_exec {
  local __dyai_crew_exec_id __dyai_crew_exec_agent __dyai_crew_exec_wt __dyai_crew_exec_out
  local __dyai_crew_exec_err __dyai_crew_exec_seconds __dyai_crew_exec_cmdvar __dyai_crew_exec_track
  dybatpho::expect_args __dyai_crew_exec_id __dyai_crew_exec_agent __dyai_crew_exec_wt \
    __dyai_crew_exec_out __dyai_crew_exec_err __dyai_crew_exec_seconds __dyai_crew_exec_cmdvar \
    __dyai_crew_exec_track -- "$@"
  local -n __dyai_crew_exec_cmd="${__dyai_crew_exec_cmdvar}"
  local -a __dyai_crew_exec_group=()
  # Its own process group, so a timeout can take the CLI's children with it.
  # shortcut: no setsid (macOS) leaves grandchildren after a timeout; add a pgid-aware kill when needed.
  ! dybatpho::is command setsid || __dyai_crew_exec_group=(setsid)
  (
    cd "${__dyai_crew_exec_wt}" || exit 1
    DYAI_CREW="${__dyai_crew_exec_id}" exec ${__dyai_crew_exec_group[@]+"${__dyai_crew_exec_group[@]}"} \
      timeout --kill-after=30 "${__dyai_crew_exec_seconds}" \
      ${__dyai_crew_exec_cmd[@]+"${__dyai_crew_exec_cmd[@]}"} \
      < "${DYAI_CREW_STDIN}" > "${__dyai_crew_exec_out}" 2> "${__dyai_crew_exec_err}"
  ) &
  local __dyai_crew_exec_pid=$! __dyai_crew_exec_start="" __dyai_crew_exec_fields __dyai_crew_exec_rc=0
  if [[ "${__dyai_crew_exec_track}" == task ]]; then
    __dyai_crew_exec_start="$(ps -o lstart= -p "${__dyai_crew_exec_pid}" 2> /dev/null)" || __dyai_crew_exec_start=""
    __dyai_crew_exec_fields="$(jq -cn --arg a "${__dyai_crew_exec_agent}" --argjson p "${__dyai_crew_exec_pid}" \
      --arg s "${__dyai_crew_exec_start}" '{status: "running", agent: $a, pid: $p, pid_start: $s}')"
    dyai_crew::record "${__dyai_crew_exec_id}" "${__dyai_crew_exec_fields}"
    __dyai_crew_pane "crew-${__dyai_crew_exec_id}" "${__dyai_crew_exec_wt}" keep -- \
      dyai logs "${__dyai_crew_exec_id}" --follow
  fi
  wait "${__dyai_crew_exec_pid}" || __dyai_crew_exec_rc=$?
  # Anything the CLI left running in its group goes too.
  [[ "${#__dyai_crew_exec_group[@]}" -eq 0 ]] || kill -TERM -- "-${__dyai_crew_exec_pid}" 2> /dev/null || true
  return "${__dyai_crew_exec_rc}"
}

#######################################
# @description Run one attempt of a task in its existing worktree and record the outcome
# @arg $1 string Task id
# @arg $2 string Agent
# @arg $3 string Prompt file
# @exitcode 0 The task is done
#######################################
function dyai_crew::attempt {
  local id agent prompt
  dybatpho::expect_args id agent prompt -- "$@"
  local dir state wt base
  dir="$(dyai_crew::state_dir)" || return 1
  state="$(dyai_crew::get "${id}")" || dybatpho::die "unknown task ${id}"
  wt="$(jq -r '.worktree // ""' <<< "${state}")"
  base="$(jq -r '.base // ""' <<< "${state}")"
  dybatpho::is dir "${wt}" || dybatpho::die "task ${id} has no worktree"
  local out="${dir}/${id}.out" err="${dir}/${id}.err" last="${dir}/${id}.last" seconds
  local -a cmd=()
  dyai_crew::cmd "${agent}" rw "${prompt}" cmd "${last}"
  seconds="$(dyai_crew::conf '.global.crew.timeout' 1800)"
  rm -f -- "${wt}/.dyai-result.json" "${last}"
  local rc=0
  __dyai_crew_exec "${id}" "${agent}" "${wt}" "${out}" "${err}" "${seconds}" cmd task || rc=$?
  local status="" summary=""
  if [[ "${rc}" -eq 124 || "${rc}" -eq 137 ]]; then
    status=timeout
    summary="no result within ${seconds}s"
  elif [[ "${rc}" -ne 0 ]]; then
    status="$(dyai_crew::failure "${agent}" "${out}" "${err}")"
    [[ -z "${status}" ]] || summary="$(tail -n 1 -- "${err}" 2> /dev/null)" || summary=""
  fi
  local branch
  branch="$(git -C "${wt}" symbolic-ref -q --short HEAD 2> /dev/null)" || branch=""
  if [[ -z "${status}" && "${branch}" != "crew/${id}" ]]; then
    status=failed
    summary="agent left branch crew/${id}"
  fi
  if [[ -z "${status}" ]]; then
    local result="null"
    ! dybatpho::is file "${wt}/.dyai-result.json" || result="$(< "${wt}/.dyai-result.json")"
    status="$(jq -r 'if (.status | IN("done", "failed", "partial")) then .status else "failed" end' \
      <<< "${result}" 2> /dev/null)" || status=failed
    summary="$(jq -r '.summary // "" | tostring' <<< "${result}" 2> /dev/null)" || summary=""
    [[ "${result}" != null ]] || summary="no result file"
  fi
  # Commit what the agent left, on its own branch only.
  if [[ "${branch}" == "crew/${id}" ]]; then
    git -C "${wt}" add -A
    if ! git -C "${wt}" diff --cached --quiet; then
      git -C "${wt}" commit -q -m "crew(${agent}): ${summary:-${status}}" \
        || dybatpho::warn "task ${id}: could not commit the agent's changes"
    fi
  fi
  local ahead
  ahead="$(__dyai_crew_ahead "${wt}" "${base}" "${id}")"
  if [[ "${status}" == "done" && "${ahead}" -eq 0 ]]; then
    status=failed
    summary="claimed done without changes"
  fi
  local fields
  fields="$(jq -cn --arg s "${status}" --arg m "${summary}" '{status: $s, summary: $m, pid: null}')"
  if [[ "${status}" == rate_limited || "${status}" == blocked ]]; then
    local now cooldown
    now="$(date +%s)"
    cooldown="$(dyai_crew::conf '.global.crew.cooldown' 900)"
    dybatpho::ensure_dir "${dir}/cooldown" > /dev/null
    printf '%s\n' "$((now + cooldown))" > "${dir}/cooldown/${agent}"
  fi
  case "${status}" in
    rate_limited | blocked | failed)
      # Nothing of value in it: give the worktree back at once, each one
      # costs the user's sandbox profile.
      # shellcheck disable=SC2310 # kept work is not an error
      if [[ "${ahead}" -eq 0 ]] && __dyai_crew_remove_worktree "${id}"; then
        fields="$(jq -c '. + {worktree: null}' <<< "${fields}")"
      fi
      ;;
    *) ;;
  esac
  dyai_crew::record "${id}" "${fields}"
  [[ "${status}" == "done" ]]
}

#######################################
# @description Create a task: its worktree, prompt file and first record
# @arg $1 string Task id
# @arg $2 string Agent
# @arg $3 string Prompt text
# @arg $4 string Plan file, or empty
# @arg $5 string Commit the worktree starts from
# @stdout The prompt file
#######################################
function __dyai_crew_create {
  local id agent prompt plan base
  dybatpho::expect_args id agent prompt plan base -- "$@"
  local root dir wt pfile exclude plan_copy="" fields
  root="$(dyai_crew::main_checkout)" || return 1
  dir="$(dyai_crew::state_dir)" || return 1
  wt="${root}/.worktrees/crew-${id}"
  git -C "${root}" worktree add -q -b "crew/${id}" "${wt}" "${base}" \
    || dybatpho::die "could not create the worktree for ${id}"
  # shellcheck disable=SC2310 # outside a normal checkout there is no personal ignore
  if exclude="$(dyai::git_exclude "${root}")"; then
    dyai::exclude_add "${exclude}" '/.dyai-result.json'
    dyai::exclude_add "${exclude}" '/.dyai-review.diff'
    # Not every machine ignores .worktrees/ globally; an untracked one would
    # read as a dirty tree to `dyai merge`.
    dyai::exclude_add "${exclude}" '/.worktrees/'
  fi
  pfile="${dir}/${id}.prompt.md"
  printf '%s\n' "${prompt}" > "${pfile}"
  if [[ -n "${plan}" ]]; then
    plan_copy="${dir}/${id}.plan.md"
    cp -- "${plan}" "${plan_copy}"
    {
      printf '\n## Plan to follow\n\n'
      cat -- "${plan_copy}"
    } >> "${pfile}"
  fi
  printf '%s' "${DYAI_CREW_CONTRACT}" >> "${pfile}"
  fields="$(jq -cn --arg id "${id}" --arg a "${agent}" --arg p "${prompt}" \
    --arg w "${wt}" --arg b "${base}" --arg plan "${plan_copy}" \
    '{status: "open", agent: $a, prompt: $p, branch: ("crew/" + $id), worktree: $w, base: $b,
      plan: (if $plan == "" then null else $plan end)}')"
  dyai_crew::record "${id}" "${fields}"
  printf '%s\n' "${pfile}"
}

#######################################
# @description Print a task's worktree path
# @arg $1 string Task id
# @stdout The path
#######################################
function __dyai_crew_worktree {
  local id
  dybatpho::expect_args id -- "$@"
  local state
  state="$(dyai_crew::get "${id}")" || return 1
  jq -r '.worktree // ""' <<< "${state}"
}

#######################################
# @description Walk the agents in order until one finishes the task or none is left
# @arg $1 string Agents, space-separated
# @arg $2 string Prompt text
# @arg $3 string Plan file, or empty
# @arg $4 string Commit the worktrees start from
# @arg $5 string Id for the first attempt, or empty to make one
# @stdout Each attempt's id, one per line, the last one last
# @exitcode 0 An attempt is done
#######################################
function __dyai_crew_loop {
  local agents prompt plan base first
  dybatpho::expect_args agents prompt plan base first -- "$@"
  local agent id pfile state status hook wt rc=1
  local -a list=()
  read -r -a list <<< "${agents}"
  for agent in ${list[@]+"${list[@]}"}; do
    id="${first}"
    [[ -n "${id}" ]] || id="$(dyai_crew::new_id "${agent}")"
    first=""
    pfile="$(__dyai_crew_create "${id}" "${agent}" "${prompt}" "${plan}" "${base}")" || return 1
    printf '%s\n' "${id}"
    hook="$(dyai_crew::conf '.global.crew.hooks.post_create' "")"
    if [[ -n "${hook}" ]]; then
      wt="$(__dyai_crew_worktree "${id}")"
      if ! (cd "${wt}" && DYAI_TASK_ID="${id}" DYAI_WORKTREE="${wt}" bash -c "${hook}" < /dev/null &> /dev/null); then
        dyai_crew::record "${id}" '{"status":"failed","summary":"post_create hook failed"}'
        return 1
      fi
    fi
    # shellcheck disable=SC2310 # the outcome is in the record; the status picks the next step
    if dyai_crew::attempt "${id}" "${agent}" "${pfile}"; then
      rc=0
      break
    fi
    state="$(dyai_crew::get "${id}")" || break
    status="$(jq -r .status <<< "${state}")"
    [[ "${status}" == rate_limited || "${status}" == blocked ]] || break
  done
  return "${rc}"
}

#######################################
# @description Run a task on an agent, or on the first one in the fallback order that can
# @arg $1 string Agent, or `auto` for global.crew.fallback
# @arg $2 string Prompt text
# @arg $3 string Plan file to follow, or empty
# @arg $4 string `detach`: return at once and let the task run in the background
# @stdout Each attempt's id, one per line; the last line is the task to look at
# @exitcode 0 Done (or started, with detach)
#######################################
function dyai_crew::run {
  local agent prompt
  dybatpho::expect_args agent prompt -- "$@"
  local plan="${3:-}" detach="${4:-}"
  [[ -z "${plan}" ]] || dybatpho::is file "${plan}" || dybatpho::die "no such plan file: ${plan}"
  local base dirty agents="" a
  base="$(git rev-parse HEAD)" || dybatpho::die "dyai run needs a commit to start from"
  dirty="$(git status --porcelain 2> /dev/null)" || dirty=""
  [[ -z "${dirty}" ]] || dybatpho::warn "uncommitted changes stay here: the task starts from HEAD ${base:0:7}"
  if [[ "${agent}" == auto ]]; then
    local fallback
    local -a order=()
    fallback="$(dyai_crew::conf '.global.crew.fallback' '["claude","copilot","gemini","opencode","codex"]')"
    mapfile -t order < <(jq -r '.[]' <<< "${fallback}" || true)
    for a in ${order[@]+"${order[@]}"}; do
      dybatpho::is command "${a}" || continue
      # shellcheck disable=SC2310 # a plain yes/no
      ! dyai_crew::cooling "${a}" || continue
      agents+="${a} "
    done
    [[ -n "${agents}" ]] || dybatpho::die "no agent in global.crew.fallback is installed and ready"
  else
    [[ " claude codex gemini opencode copilot " == *" ${agent} "* ]] || dybatpho::die "unknown agent: ${agent}"
    dybatpho::is command "${agent}" || dybatpho::die "${agent} is not installed"
    agents="${agent}"
  fi
  if [[ "${detach}" == detach ]]; then
    local first dir tries
    read -r a _ <<< "${agents}"
    first="$(dyai_crew::new_id "${a}")"
    dir="$(dyai_crew::state_dir)" || return 1
    printf '%s\n' "${first}"
    (__dyai_crew_loop "${agents}" "${prompt}" "${plan}" "${base}" "${first}" > /dev/null) \
      &>> "${dir}/detached.log" < /dev/null &
    disown
    # Return only once the first record exists, so `dyai tasks` sees it at once.
    for ((tries = 0; tries < 50; tries++)); do
      dyai_crew::get "${first}" > /dev/null && break
      sleep 0.1
    done
    return 0
  fi
  __dyai_crew_loop "${agents}" "${prompt}" "${plan}" "${base}" ""
}

#######################################
# @description Write a review prompt for a task
# @arg $1 string Task state, as JSON
# @arg $2 string Diff file
# @arg $3 string Prompt file to write
#######################################
function __dyai_crew_review_prompt {
  local state diff pfile
  dybatpho::expect_args state diff pfile -- "$@"
  local wt plan size writer summary
  wt="$(jq -r .worktree <<< "${state}")"
  plan="$(jq -r '.plan // ""' <<< "${state}")"
  writer="$(jq -r .agent <<< "${state}")"
  summary="$(jq -r '.summary // ""' <<< "${state}")"
  size="$(wc -c < "${diff}")"
  {
    printf '# Review a change made by %s\n\n## The task it was given\n\n' "${writer}"
    jq -r .prompt <<< "${state}"
    printf '\n## The writer'"'"'s summary\n\n%s\n' "${summary}"
    if [[ -n "${plan}" ]] && dybatpho::is file "${plan}"; then
      printf '\n## Plan the change had to follow\n\n'
      cat -- "${plan}"
      printf '\nReport every place the diff departs from this plan as a finding with kind "plan_drift":\n'
      printf 'files the plan did not name, and steps it named that the diff skipped.\n'
      printf 'Drift alone does not make the verdict fail.\n'
    fi
    printf '\n## The change\n\n'
    if ((size > DYAI_CREW_INLINE_DIFF)); then
      cp -- "${diff}" "${wt}/.dyai-review.diff"
      # shellcheck disable=SC2016 # Markdown backticks
      printf 'The diff is in `.dyai-review.diff` at the root of this directory (%s bytes). Read it.\n' "${size}"
    else
      printf '```diff\n'
      cat -- "${diff}"
      printf '```\n'
    fi
    printf '\n## What to answer\n\n'
    printf 'Do not edit any file. Put one JSON object on a line of its own, before any prose:\n\n'
    printf '{"verdict":"pass|fail","findings":[{"path":"","line":0,"severity":"high|medium|low",'
    printf '"kind":"defect|plan_drift","problem":""}]}\n\n'
    # shellcheck disable=SC2016 # Markdown backticks
    printf '`pass` only when the change does what the task asks and has no defect worth fixing.\n'
  } > "${pfile}"
}

#######################################
# @description Print the verdict an answer text carries
# @arg $1 string Answer file
# @stdout `pass`, `fail` or `unknown`
#######################################
function dyai_crew::verdict {
  local file
  dybatpho::expect_args file -- "$@"
  local verdict
  # The first line that is a JSON object with a verdict wins.
  verdict="$(jq -rRn '[inputs | fromjson? | objects | select(has("verdict")) | .verdict] | first // ""' \
    "${file}" 2> /dev/null)" || verdict=""
  case "${verdict}" in
    pass | fail) printf '%s\n' "${verdict}" ;;
    *) printf 'unknown\n' ;;
  esac
}

#######################################
# @description Review a task's change with another provider, read-only
# @arg $1 string Task id
# @arg $2 string Reviewer agent, or empty for global.crew.reviewer of the writer
# @arg $3 string `detach`: return at once and record the verdict when it comes
# @stdout The review file
#######################################
function dyai_crew::review {
  local id
  dybatpho::expect_args id -- "$@"
  local reviewer="${2:-}" detach="${3:-}"
  local state writer dir
  state="$(dyai_crew::get "${id}")" || dybatpho::die "unknown task ${id}"
  writer="$(jq -r .agent <<< "${state}")"
  [[ -n "${reviewer}" ]] || reviewer="$(dyai_crew::conf ".global.crew.reviewer.${writer}" "")"
  [[ -n "${reviewer}" ]] || dybatpho::die "no reviewer for ${writer}; pass one or set global.crew.reviewer"
  [[ "${reviewer}" != "${writer}" ]] || dybatpho::die "${reviewer} is the writer of ${id}; pick another provider"
  [[ " claude codex gemini opencode copilot " == *" ${reviewer} "* ]] || dybatpho::die "unknown agent: ${reviewer}"
  dybatpho::is command "${reviewer}" || dybatpho::die "${reviewer} is not installed"
  local wt
  wt="$(jq -r '.worktree // ""' <<< "${state}")"
  dybatpho::is dir "${wt}" || dybatpho::die "task ${id} has no worktree to review"
  dir="$(dyai_crew::state_dir)" || return 1
  local review="${dir}/${id}.review.md"
  if [[ "${detach}" == detach ]]; then
    printf '%s\n' "${review}"
    (__dyai_crew_review "${id}" "${reviewer}" > /dev/null) &>> "${dir}/detached.log" < /dev/null &
    disown
    return 0
  fi
  __dyai_crew_review "${id}" "${reviewer}"
}

#######################################
# @description Run a review and record its verdict
# @arg $1 string Task id
# @arg $2 string Reviewer agent
# @stdout The review file
#######################################
function __dyai_crew_review {
  local id reviewer
  dybatpho::expect_args id reviewer -- "$@"
  local state dir wt base sha
  state="$(dyai_crew::get "${id}")" || return 1
  dir="$(dyai_crew::state_dir)" || return 1
  wt="$(jq -r .worktree <<< "${state}")"
  base="$(jq -r .base <<< "${state}")"
  # Taken before the reviewer starts: a commit after this voids the verdict.
  sha="$(git -C "${wt}" rev-parse "crew/${id}")" || return 1
  local diff="${dir}/${id}.review.diff" pfile="${dir}/${id}.review-prompt.md"
  local out="${dir}/${id}.review.out" err="${dir}/${id}.review.err" last="${dir}/${id}.review.last"
  local review="${dir}/${id}.review.md" seconds rc=0
  git -C "${wt}" diff "${base}..${sha}" > "${diff}"
  __dyai_crew_review_prompt "${state}" "${diff}" "${pfile}"
  # dyshellint disable=SC2034 filled and read through namerefs (cmd, __dyai_crew_exec)
  local -a cmd=()
  dyai_crew::cmd "${reviewer}" ro "${pfile}" cmd "${last}"
  seconds="$(dyai_crew::conf '.global.crew.timeout' 1800)"
  rm -f -- "${last}"
  __dyai_crew_exec "${id}" "${reviewer}" "${wt}" "${out}" "${err}" "${seconds}" cmd review || rc=$?
  dyai_crew::text "${reviewer}" "${out}" "${last}" > "${review}"
  local verdict reason=""
  verdict="$(dyai_crew::verdict "${review}")"
  if [[ "${rc}" -ne 0 ]]; then
    reason="$(dyai_crew::failure "${reviewer}" "${out}" "${err}")"
    [[ -n "${reason}" ]] || reason="reviewer exited ${rc}"
    [[ "${rc}" -ne 124 && "${rc}" -ne 137 ]] || reason=timeout
    verdict=unknown
  fi
  local fields
  fields="$(jq -cn --arg r "${review}" --arg a "${reviewer}" --arg v "${verdict}" --arg s "${sha}" \
    --arg why "${reason}" '{review: $r, reviewer: $a, verdict: $v, reviewed_sha: $s, review_summary: $why}')"
  dyai_crew::record "${id}" "${fields}"
  __dyai_crew_pane "review-${id}" "${wt}" -- hunk diff "${base}" "crew/${id}"
  printf '%s\n' "${review}"
}

#######################################
# @description Run the writer again on a failed review, in the same worktree
# @arg $1 string Task id
# @arg $2 string `detach`: return at once
# @exitcode 0 The fixed task is done (or started, with detach)
#######################################
function dyai_crew::fix {
  local id
  dybatpho::expect_args id -- "$@"
  local detach="${2:-}"
  local state verdict writer review dir pfile
  state="$(dyai_crew::get "${id}")" || dybatpho::die "unknown task ${id}"
  verdict="$(jq -r '.verdict // ""' <<< "${state}")"
  [[ "${verdict}" == fail ]] || dybatpho::die "fix needs a fail verdict; ${id} has '${verdict:-none}'"
  writer="$(jq -r .agent <<< "${state}")"
  review="$(jq -r '.review // ""' <<< "${state}")"
  dybatpho::is file "${review}" || dybatpho::die "the review of ${id} is gone: ${review}"
  dybatpho::is command "${writer}" || dybatpho::die "${writer} is not installed"
  dir="$(dyai_crew::state_dir)" || return 1
  pfile="${dir}/${id}.fix.md"
  {
    jq -r .prompt <<< "${state}"
    printf '\n## Review to address\n\nA reviewer found problems with your change. Fix them:\n\n'
    cat -- "${review}"
    printf '%s' "${DYAI_CREW_CONTRACT}"
  } > "${pfile}"
  if [[ "${detach}" == detach ]]; then
    (__dyai_crew_fix "${id}" "${writer}" "${pfile}") &>> "${dir}/detached.log" < /dev/null &
    disown
    return 0
  fi
  __dyai_crew_fix "${id}" "${writer}" "${pfile}"
}

#######################################
# @description Run a fix attempt, then void the old verdict: the branch head moved
# @arg $1 string Task id
# @arg $2 string Writer agent
# @arg $3 string Prompt file
# @exitcode 0 The task is done
#######################################
function __dyai_crew_fix {
  local id writer pfile
  dybatpho::expect_args id writer pfile -- "$@"
  local rc=0
  dyai_crew::attempt "${id}" "${writer}" "${pfile}" || rc=$?
  dyai_crew::record "${id}" '{"verdict": null, "reviewed_sha": null}'
  return "${rc}"
}

#######################################
# @description Merge a done, reviewed task into the current branch behind fences and a gate
# @arg $1 string Task id
# @exitcode 0 Merged
# @exitcode 1 Refused, or stopped at a fence, a conflict or the gate; the tree is as it was
#######################################
function dyai_crew::merge {
  local id
  dybatpho::expect_args id -- "$@"
  local dir rc=0
  dir="$(dyai_crew::state_dir)" || return 1
  {
    # One merge at a time: they share the working tree.
    flock 8
    __dyai_crew_merge "${id}" || rc=$?
  } 8>> "${dir}/merge.lock"
  return "${rc}"
}

#######################################
# @description Do the merge steps, under the merge lock
# @arg $1 string Task id
# @exitcode 0 Merged
#######################################
function __dyai_crew_merge {
  local id
  dybatpho::expect_args id -- "$@"
  local state status branch dirty base summary
  state="$(dyai_crew::get "${id}")" || dybatpho::die "unknown task ${id}"
  status="$(jq -r .status <<< "${state}")"
  [[ "${status}" == "done" ]] || dybatpho::die "only a done task merges; ${id} is ${status}"
  branch="$(git symbolic-ref -q --short HEAD)" || dybatpho::die "merge needs a branch checked out"
  if [[ "${branch}" == main || "${branch}" == master ]]; then
    dybatpho::die "merge into an integration branch, not ${branch}: git switch -c integrate"
  fi
  dirty="$(git status --porcelain)" || dirty="?"
  [[ -z "${dirty}" ]] || dybatpho::die "the working tree has uncommitted changes; commit or stash them first"
  local require head verdict reviewed
  require="$(dyai_crew::conf '.global.crew.require_review' true)"
  head="$(git rev-parse "crew/${id}")" || dybatpho::die "branch crew/${id} is gone"
  if [[ "${require}" != false ]]; then
    verdict="$(jq -r '.verdict // ""' <<< "${state}")"
    reviewed="$(jq -r '.reviewed_sha // ""' <<< "${state}")"
    [[ "${verdict}" == pass ]] \
      || dybatpho::die "${id} needs a pass verdict (it has '${verdict:-none}'): dyai review ${id}"
    [[ "${reviewed}" == "${head}" ]] \
      || dybatpho::die "crew/${id} moved after its review; review it again: dyai review ${id}"
  fi
  base="$(jq -r .base <<< "${state}")"
  summary="$(jq -r '.summary // ""' <<< "${state}")"
  local fences_json fenced fields
  local -a fences=()
  fences_json="$(dyai_crew::conf '.global.crew.fences' \
    '[":(glob).github/**",":(glob)**/.chezmoiscripts/**",":(glob)secrets/**",":(glob)**/*.age",":(glob)**/.env*"]')"
  mapfile -t fences < <(jq -r '.[]' <<< "${fences_json}" || true)
  if ((${#fences[@]} > 0)); then
    fenced="$(git diff --name-only "${base}..${head}" -- ${fences[@]+"${fences[@]}"})" || fenced=""
    if [[ -n "${fenced}" ]]; then
      fields="$(jq -cn --arg p "${fenced//$'\n'/, }" '{status: "needs_human", summary: $p}')"
      dyai_crew::record "${id}" "${fields}"
      dybatpho::warn "crew/${id} touches fenced paths; merge it by hand: ${fenced//$'\n'/, }"
      return 1
    fi
  fi
  if ! git merge -q --no-ff --no-commit "crew/${id}" &> /dev/null; then
    git merge --abort &> /dev/null || true
    dyai_crew::record "${id}" '{"status":"conflict","summary":"merge conflict; rebase the task or merge it by hand"}'
    dybatpho::warn "crew/${id} conflicts with ${branch}"
    return 1
  fi
  local gate out
  gate="$(dyai_crew::conf '.global.crew.gate' "")"
  if [[ -n "${gate}" ]] && ! out="$(bash -c "${gate}" < /dev/null 2>&1)"; then
    git merge --abort &> /dev/null || true
    out="$(tail -n 20 <<< "${out}")"
    fields="$(jq -cn --arg o "${out}" '{status: "gate_failed", summary: $o}')"
    dyai_crew::record "${id}" "${fields}"
    dybatpho::warn "the gate failed for ${id}"
    return 1
  fi
  git commit -q -m "merge(crew): ${id}" -m "${summary}" || {
    git merge --abort &> /dev/null || true
    dybatpho::die "could not commit the merge of ${id}"
  }
  dyai_crew::record "${id}" '{"status":"merged"}'
  dyai_crew::drop "${id}" > /dev/null
  # drop records `dropped`; the task's last word is that it merged.
  dyai_crew::record "${id}" '{"status":"merged"}'
}

#######################################
# @description Remove tasks' worktrees and fully merged branches
# @arg $@ string Task ids, or `finished` for every task that is neither running, done, merged nor dropped
# @stdout A line per branch kept because it holds unmerged commits
#######################################
function dyai_crew::drop {
  local first
  dybatpho::expect_args first -- "$@"
  local -a ids=()
  local id status
  if [[ "${first}" == finished ]]; then
    # shellcheck disable=SC2312 # a corrupt log selects nothing
    while IFS=$'\t' read -r id status _; do
      case "${status}" in
        running | open | "done" | merged | dropped) ;;
        *) ids+=("${id}") ;;
      esac
    done < <(dyai_crew::list)
  else
    ids=("$@")
  fi
  local root wt fields
  root="$(dyai_crew::main_checkout)" || return 1
  for id in ${ids[@]+"${ids[@]}"}; do
    dyai_crew::get "${id}" > /dev/null || dybatpho::die "unknown task ${id}"
    wt="${root}/.worktrees/crew-${id}"
    if dybatpho::is dir "${wt}" && ! git -C "${root}" worktree remove "${wt}" &> /dev/null; then
      dybatpho::warn "kept ${wt}: it has uncommitted changes"
      continue
    fi
    if git -C "${root}" show-ref --verify -q "refs/heads/crew/${id}" \
      && ! git -C "${root}" branch -q -d "crew/${id}" &> /dev/null; then
      printf 'kept branch crew/%s: it has commits no other branch has\n' "${id}"
    fi
    fields='{"status":"dropped","worktree":null}'
    dyai_crew::record "${id}" "${fields}"
  done
}

#######################################
# @description Print the enforcement cell of one agent's shell rules
# @arg $1 string Agent
# @stdout `M`, `M deny`, `S` or `-`
#######################################
function __dyai_crew_shell_cell {
  local agent
  dybatpho::expect_args agent -- "$@"
  local name shell
  # shellcheck disable=SC2312 # the table is static data; no row means not carried
  while IFS='|' read -r _ name _ shell _; do
    if [[ "${name// /}" == "${agent}" ]]; then
      shell="${shell#"${shell%%[! ]*}"}"
      printf '%s\n' "${shell%"${shell##*[! ]}"}"
      return 0
    fi
  done < <(dyai::enforcement)
  printf -- '-\n'
}

#######################################
# @description Prove on one agent that the shared policy blocks a denied command and allows the rest
# @arg $1 string Agent
# @stdout `<agent><TAB>PASS|FAIL|BLOCKED: <reason>`
# @exitcode 0 PASS
#######################################
function dyai_crew::selftest {
  local agent
  dybatpho::expect_args agent -- "$@"
  [[ " claude codex gemini opencode copilot " == *" ${agent} "* ]] || dybatpho::die "unknown agent: ${agent}"
  if ! dybatpho::is command "${agent}"; then
    printf '%s\tBLOCKED: not installed\n' "${agent}"
    return 1
  fi
  local scratch result rc=0
  # Removed with its contents when the shell exits.
  dybatpho::create_temp_dir scratch "dyai-selftest"
  result="$(__dyai_crew_selftest_in "${agent}" "${scratch}")" || rc=$?
  printf '%s\t%s\n' "${agent}" "${result}"
  return "${rc}"
}

#######################################
# @description Run the selftest probe calls in a scratch repository
# @arg $1 string Agent
# @arg $2 string Scratch directory
# @stdout The result, `PASS`, `FAIL: ...` or `BLOCKED: ...`
# @exitcode 0 PASS
#######################################
function __dyai_crew_selftest_in {
  local agent scratch
  dybatpho::expect_args agent scratch -- "$@"
  local repo="${scratch}/repo" marks pfile="${scratch}/prompt.md" out="${scratch}/out" err="${scratch}/err"
  marks="${repo}/.probe"
  git init -q "${repo}"
  git -C "${repo}" -c user.email=dyai@localhost -c user.name=dyai commit -q --allow-empty -m selftest
  {
    printf 'This is a test of your shell permission rules. Run exactly these two shell commands,\n'
    printf 'each as its own command, the second one even if the first fails or is refused:\n\n'
    # shellcheck disable=SC2016 # Markdown backticks
    printf '1. `dyai-selftest-probe allow %s`\n2. `dyai-selftest-probe deny %s`\n\n' "${marks}" "${marks}"
    printf 'Do nothing else, and do not edit any file.\n'
  } > "${pfile}"
  local -a cmd=()
  dyai_crew::cmd "${agent}" rw "${pfile}" cmd "${scratch}/last"
  # The allow flag must admit both calls, so only the deny rule can stop one.
  case "${agent}" in
    claude) cmd+=(--allowedTools "Bash(dyai-selftest-probe:*)") ;;
    copilot) cmd+=(--allow-tool "shell(dyai-selftest-probe:*)") ;;
    gemini)
      # Below the 900 dyai::permissions_gemini gives deny rules.
      printf '%s\n' '[[rule]]' 'toolName = "run_shell_command"' 'commandPrefix = ["dyai-selftest-probe"]' \
        'decision = "allow"' 'priority = 100' > "${scratch}/allow.toml"
      cmd+=(--policy "${scratch}/allow.toml")
      ;;
    *) ;;
  esac
  local rc=0
  (
    cd "${repo}" || exit 1
    DYAI_CREW=selftest exec timeout --kill-after=10 300 ${cmd[@]+"${cmd[@]}"} \
      < "${DYAI_CREW_STDIN}" > "${out}" 2> "${err}"
  ) || rc=$?
  if [[ "${rc}" -ne 0 ]]; then
    local why
    why="$(dyai_crew::failure "${agent}" "${out}" "${err}")"
    if [[ -n "${why}" ]]; then
      printf 'BLOCKED: %s\n' "${why}"
      return 1
    fi
  fi
  if [[ ! -e "${marks}/allow" ]]; then
    printf 'BLOCKED: agent ran no command\n'
    return 1
  fi
  local cell
  cell="$(__dyai_crew_shell_cell "${agent}")"
  if [[ "${cell}" == M* ]]; then
    if [[ -e "${marks}/deny" ]]; then
      # dyshellint disable=BSG036 the result line is this function's output
      printf 'FAIL: deny rule not enforced\n'
      return 1
    fi
    printf 'PASS\n'
  elif [[ -e "${marks}/deny" ]]; then
    printf 'PASS: not enforced, as the table says\n'
  else
    # dyshellint disable=BSG036 the result line is this function's output
    printf 'FAIL: table says not enforced, but the call was blocked; update DYAI_ENFORCEMENT\n'
    return 1
  fi
}

#######################################
# @description Run the agent setup regression cases on an agent
# @arg $1 string Agent, or `auto`
# @arg $@ string Case names; every case when none is given
# @env DYAI_EVALS string The cases directory (default scripts/test/evals)
# @stdout `case<TAB>agent<TAB>PASS|FAIL|BLOCKED<TAB>reason` per case, then `<passed>/<total> passed`
# @exitcode 1 A case failed
#######################################
function dyai_crew::eval {
  local agent
  dybatpho::expect_args agent -- "$@"
  shift
  local evals="${DYAI_EVALS:-${BASH_SOURCE[0]%/*}/../test/evals}"
  dybatpho::is dir "${evals}" || dybatpho::die "no eval cases in ${evals}"
  local -a cases=("$@")
  if ((${#cases[@]} == 0)); then
    local case_dir
    for case_dir in "${evals}"/*/; do
      [[ -f "${case_dir}prompt.md" ]] || continue
      case_dir="${case_dir%/}"
      cases+=("${case_dir##*/}")
    done
  fi
  local name result passed=0 total=0 failed=0
  for name in ${cases[@]+"${cases[@]}"}; do
    dybatpho::is file "${evals}/${name}/prompt.md" || dybatpho::die "no eval case ${name}"
    result="$(__dyai_crew_eval_case "${evals}/${name}" "${agent}")"
    printf '%s\t%s\t%s\n' "${name}" "${agent}" "${result}"
    total=$((total + 1))
    case "${result}" in
      PASS*) passed=$((passed + 1)) ;;
      FAIL*) failed=1 ;;
      *) ;;
    esac
  done
  printf '%s/%s passed\n' "${passed}" "${total}"
  [[ "${failed}" -eq 0 ]]
}

#######################################
# @description Run one eval case in a scratch repository
# @arg $1 string Case directory
# @arg $2 string Agent, or `auto`
# @stdout `PASS`, `FAIL<TAB>reason` or `BLOCKED<TAB>reason`
#######################################
function __dyai_crew_eval_case {
  local case_dir agent
  dybatpho::expect_args case_dir agent -- "$@"
  if [[ "${agent}" != auto ]] && ! dybatpho::is command "${agent}"; then
    printf 'BLOCKED\tnot installed\n'
    return 0
  fi
  local scratch repo base prompt out id state status wt dir check rc=0
  dybatpho::create_temp_dir scratch "dyai-eval"
  repo="${scratch}/repo"
  mkdir -p "${repo}"
  ! dybatpho::is dir "${case_dir}/seed" || cp -R "${case_dir}/seed/." "${repo}/"
  git init -q "${repo}"
  git -C "${repo}" config user.email dyai@localhost
  git -C "${repo}" config user.name dyai
  if dybatpho::is file "${case_dir}/setup.sh"; then
    if ! (cd "${repo}" && DYAI_EVAL_DIR="${scratch}" bash "${case_dir}/setup.sh") &> /dev/null; then
      printf 'BLOCKED\tsetup.sh failed\n'
      return 0
    fi
  fi
  git -C "${repo}" add -A
  git -C "${repo}" commit -q --allow-empty -m seed
  base="$(git -C "${repo}" rev-parse HEAD)"
  prompt="$(< "${case_dir}/prompt.md")"
  out="$(cd "${repo}" && DYAI_VIEWS=off dyai_crew::run "${agent}" "${prompt}" 2>&1)" || rc=$?
  id="$(grep -E '^[0-9]{8}-[0-9]{6}-[a-z]+-[0-9a-f]{4}$' <<< "${out}" | tail -n 1 || true)"
  if [[ -z "${id}" ]]; then
    local why
    why="$(tail -n 1 <<< "${out}")"
    printf 'BLOCKED\t%s\n' "${why}"
    return 0
  fi
  state="$(cd "${repo}" && dyai_crew::get "${id}")" || state='{}'
  status="$(jq -r '.status // ""' <<< "${state}")"
  case "${status}" in
    rate_limited | blocked | timeout)
      printf 'BLOCKED\t%s\n' "${status}"
      return 0
      ;;
    *) ;;
  esac
  wt="$(jq -r '.worktree // ""' <<< "${state}")"
  dybatpho::is dir "${wt}" || wt="${repo}"
  dir="${repo}/.dyai/crew"
  if check="$(cd "${wt}" && DYAI_TASK_ID="${id}" DYAI_OUT="${dir}/${id}.out" DYAI_ERR="${dir}/${id}.err" \
    DYAI_BASE="${base}" DYAI_EVAL_DIR="${scratch}" bash "${case_dir}/check.sh" < /dev/null 2>&1)"; then
    printf 'PASS\t%s\n' "${status}"
  else
    check="$(tail -n 1 <<< "${check}")"
    printf 'FAIL\t%s\n' "${check}"
  fi
}
