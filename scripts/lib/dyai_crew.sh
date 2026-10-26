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
  local out="${dir}/${id}.out" err="${dir}/${id}.err" last="${dir}/${id}.last" seconds panes
  local -a cmd=()
  dyai_crew::cmd "${agent}" rw "${prompt}" cmd "${last}"
  seconds="$(dyai_crew::conf '.global.crew.timeout' 1800)"
  panes="$(dyai_crew::conf '.global.crew.panes' auto)"
  rm -f -- "${wt}/.dyai-result.json" "${last}"
  local -a group=()
  # Its own process group, so a timeout can take the CLI's children with it.
  # shortcut: no setsid (macOS) leaves grandchildren after a timeout; add a pgid-aware kill when needed.
  ! dybatpho::is command setsid || group=(setsid)
  (
    cd "${wt}" || exit 1
    DYAI_CREW="${id}" exec ${group[@]+"${group[@]}"} timeout --kill-after=30 "${seconds}" \
      ${cmd[@]+"${cmd[@]}"} < "${DYAI_CREW_STDIN}" > "${out}" 2> "${err}"
  ) &
  local pid=$! start="" fields rc=0
  start="$(ps -o lstart= -p "${pid}" 2> /dev/null)" || start=""
  fields="$(jq -cn --arg a "${agent}" --argjson p "${pid}" --arg s "${start}" \
    '{status: "running", agent: $a, pid: $p, pid_start: $s}')"
  dyai_crew::record "${id}" "${fields}"
  if [[ "${panes}" == auto ]]; then
    # shellcheck disable=SC2310 # no terminal to show the log in is fine
    dyai_zellij::open "crew-${id}" "${wt}" keep -- dyai logs "${id}" --follow || true
  fi
  wait "${pid}" || rc=$?
  # Anything the CLI left running in its group goes too.
  [[ "${#group[@]}" -eq 0 ]] || kill -TERM -- "-${pid}" 2> /dev/null || true
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
