# dyshellint disable=SC2154 DOTFILES_DIR, HOME and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/dyai.sh"
  . "${DOTFILES_DIR}/scripts/lib/dyai_zellij.sh"
  . "${DOTFILES_DIR}/scripts/lib/dyai_crew.sh"
  FIX="${DOTFILES_DIR}/scripts/test/fixtures/crew"
  # Only the stubs and the system tools: a real agent CLI on the host must
  # never run here. jq and yq are linked one by one, since their own directory
  # (often ~/.local/bin) may hold real agent CLIs too.
  local tools="${BATS_TEST_TMPDIR}/tools" jq_bin yq_bin
  jq_bin="$(command -v jq)"
  yq_bin="$(command -v yq)"
  mkdir -p "${tools}"
  ln -s "${jq_bin}" "${tools}/jq"
  ln -s "${yq_bin}" "${tools}/yq"
  PATH="${HOME}/.local/bin:${tools}:/usr/bin:/bin"
  LOG="${BATS_TEST_TMPDIR}/calls"
  REPO="${BATS_TEST_TMPDIR}/repo"
  # dyshellint disable=BSG062 test_helper, loaded above, unsets GIT_DIR and its kin
  git init -q "${REPO}"
  git -C "${REPO}" config user.email t@t
  git -C "${REPO}" config user.name t
  git -C "${REPO}" commit -q --allow-empty -m init
  _crew_config 'profile: full'
  cd "${REPO}" || return 1
}

# Write the dyai config with a global.crew block; $1 holds extra crew keys.
function _crew_config {
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  printf 'global:\n  crew:\n    %s\n' "${1:-timeout: 60}" > "${HOME}/.config/dyai/config.yaml"
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
}

# Write a stub $1 on PATH that logs its argv and stdin, then runs $2.
function _stub {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "%s $*" >> "%s"\n' "${1}" "${LOG}"
    printf 'cat > "%s/%s.stdin"\n' "${BATS_TEST_TMPDIR}" "${1}"
    printf '%s\n' "${2:-true}"
  } > "${HOME}/.local/bin/${1}"
  chmod +x "${HOME}/.local/bin/${1}"
}

@test "cmd builds the claude rw line and keeps the prompt out of argv" {
  local -a c
  printf 'do it' > "${BATS_TEST_TMPDIR}/p.md"
  dyai_crew::cmd claude rw "${BATS_TEST_TMPDIR}/p.md" c
  local want="claude -p --output-format stream-json --verbose"
  want+=" --permission-mode acceptEdits --no-session-persistence"
  [[ "${c[*]}" == "${want}" ]] || fail "got: ${c[*]}"
  [[ "${DYAI_CREW_STDIN}" == "${BATS_TEST_TMPDIR}/p.md" ]]
}

@test "cmd switches each agent to its read-only mode" {
  local -a c
  local p="${BATS_TEST_TMPDIR}/p.md"
  : > "${p}"
  dyai_crew::cmd claude ro "${p}" c
  [[ " ${c[*]} " == *" --permission-mode plan "* ]]
  dyai_crew::cmd codex ro "${p}" c "${BATS_TEST_TMPDIR}/last"
  [[ "${c[*]}" == "codex exec --sandbox read-only --ephemeral --json -o ${BATS_TEST_TMPDIR}/last -" ]] || fail "${c[*]}"
  dyai_crew::cmd gemini ro "${p}" c
  [[ " ${c[*]} " == *" --approval-mode plan "* ]]
  dyai_crew::cmd opencode ro "${p}" c
  [[ " ${c[*]} " == *" --agent plan "* ]]
  dyai_crew::cmd copilot ro "${p}" c
  [[ " ${c[*]} " == *" --deny-tool shell --deny-tool write "* ]]
}

@test "cmd keeps a hostile prompt out of argv, byte for byte" {
  local p="${BATS_TEST_TMPDIR}/p.md" big
  local -a c
  big="$(printf '%204800s' '')"
  printf '%s\n' '-x "a"' "\$(touch ${BATS_TEST_TMPDIR}/pwned)" "${big// /a}" > "${p}"
  _stub claude
  dyai_crew::cmd claude rw "${p}" c
  "${c[@]}" < "${DYAI_CREW_STDIN}"
  cmp -s "${p}" "${BATS_TEST_TMPDIR}/claude.stdin" || fail "stdin differs from the prompt"
  [[ ! -e "${BATS_TEST_TMPDIR}/pwned" ]]
  run grep -c 'touch' "${LOG}"
  assert_output 0
}

@test "cmd gives opencode the prompt as an attached file" {
  local -a c
  local p="${BATS_TEST_TMPDIR}/p.md"
  : > "${p}"
  dyai_crew::cmd opencode rw "${p}" c
  [[ "${c[*]}" == "opencode run --format json -f ${p} Follow the attached task file." ]] || fail "${c[*]}"
  [[ "${DYAI_CREW_STDIN}" == /dev/null ]]
}

@test "cmd adds the configured model flag" {
  local -a c
  _crew_config 'model: {opencode: a/b, claude: opus}'
  dyai_crew::cmd opencode rw /dev/null c
  [[ " ${c[*]} " == *" -m a/b "* ]] || fail "${c[*]}"
  dyai_crew::cmd claude rw /dev/null c
  [[ " ${c[*]} " == *" --model opus "* ]] || fail "${c[*]}"
}

@test "cmd dies on an unknown agent" {
  local -a c
  run dyai_crew::cmd gpt rw /dev/null c
  assert_failure
}

@test "text extracts the answer from each agent's output" {
  local a want=$'{"verdict":"pass","findings":[]}\nLooks fine.'
  for a in claude copilot gemini opencode; do
    run dyai_crew::text "${a}" "${FIX}/${a}.verdict.out"
    assert_success
    [[ "${output}" == "${want}" ]] || fail "${a}: ${output}"
  done
  run dyai_crew::text codex "${FIX}/codex.verdict.out" "${FIX}/codex.verdict.last"
  [[ "${output}" == "${want}" ]] || fail "codex: ${output}"
}

@test "failure reads rate limits and auth errors" {
  local none="${BATS_TEST_TMPDIR}/none"
  : > "${none}"
  run dyai_crew::failure codex "${none}" "${FIX}/codex.blocked.err"
  assert_output blocked
  run dyai_crew::failure gemini "${FIX}/gemini.blocked.out" "${FIX}/gemini.blocked.err"
  assert_output blocked
  run dyai_crew::failure opencode "${FIX}/opencode.blocked.out" "${none}"
  assert_output blocked
  run dyai_crew::failure claude "${FIX}/claude.ratelimit.out" "${none}"
  assert_output rate_limited
  printf 'Error: rate limit exceeded\n' > "${BATS_TEST_TMPDIR}/err"
  run dyai_crew::failure copilot "${none}" "${BATS_TEST_TMPDIR}/err"
  assert_output rate_limited
  run dyai_crew::failure claude "${FIX}/claude.verdict.out" "${none}"
  assert_output ""
}

@test "failure ignores the word quota inside the agent's answer" {
  local none="${BATS_TEST_TMPDIR}/none"
  : > "${none}"
  printf '%s\n' '{"type":"result","is_error":false,"result":"Fixed the quota check and the 429 handler."}' \
    > "${BATS_TEST_TMPDIR}/out"
  run dyai_crew::failure claude "${BATS_TEST_TMPDIR}/out" "${none}"
  assert_output ""
}

@test "record then get returns the last state" {
  dyai_crew::record t1 '{"status":"open"}'
  dyai_crew::record t1 '{"status":"done"}'
  run dyai_crew::get t1
  assert_success
  run jq -r .status <<< "${output}"
  assert_output "done"
}

@test "get fails for an unknown id" {
  run dyai_crew::get nope
  assert_failure
}

@test "record keeps earlier fields" {
  dyai_crew::record t1 '{"agent":"claude"}'
  dyai_crew::record t1 '{"status":"done"}'
  run dyai_crew::get t1
  run jq -r '.agent + " " + .status' <<< "${output}"
  assert_output "claude done"
}

@test "parallel records on one id lose no field" {
  local n
  for n in $(seq 1 20); do
    dyai_crew::record t1 "{\"f${n}\": ${n}}" &
  done
  wait
  local dir
  dir="$(dyai_crew::state_dir)"
  run wc -l < "${dir}/tasks.jsonl"
  assert_output 20
  jq -e . "${dir}/tasks.jsonl" > /dev/null
  run dyai_crew::get t1
  run jq '[to_entries[] | select(.key | startswith("f"))] | length' <<< "${output}"
  assert_output 20
}

@test "state_dir is ignored by git and lives in the main checkout" {
  local dir
  dir="$(dyai_crew::state_dir)"
  [[ "${dir}" == "${REPO}/.dyai/crew" ]]
  git check-ignore -q .dyai/crew/x
  git worktree add -q "${REPO}/.worktrees/w" -b w
  cd "${REPO}/.worktrees/w"
  run dyai_crew::state_dir
  assert_output "${REPO}/.dyai/crew"
}

@test "record runs on_status only on a status change" {
  local out="${BATS_TEST_TMPDIR}/statuses" hook="${BATS_TEST_TMPDIR}/hook.sh"
  # shellcheck disable=SC2016 # expands when the hook runs
  printf 'printf "%%s\\n" "${DYAI_STATUS}" >> "%s"\n' "${out}" > "${hook}"
  _crew_config "hooks: {on_status: 'bash ${hook}'}"
  dyai_crew::record t1 '{"status":"running"}'
  dyai_crew::record t1 '{"summary":"x"}'
  dyai_crew::record t1 '{"status":"done"}'
  run cat "${out}"
  assert_output $'running\ndone'
}

@test "a failing on_status hook does not fail record" {
  _crew_config "hooks: {on_status: 'exit 3'}"
  run dyai_crew::record t1 '{"status":"running"}'
  assert_success
  assert_output --partial "on_status"
}

@test "list shows lost for a dead running task" {
  sleep 0 &
  local pid=$!
  wait "${pid}"
  dyai_crew::record t1 "{\"status\":\"running\",\"agent\":\"claude\",\"pid\":${pid},\"pid_start\":\"x\"}"
  dyai_crew::record t2 '{"status":"done","agent":"copilot","summary":"ok"}'
  run dyai_crew::list
  assert_success
  assert_line --index 0 $'t1\tlost\tclaude\t'
  assert_line --index 1 $'t2\tdone\tcopilot\tok'
}

# Write an agent stub $1 that logs its argv, saves its stdin, then runs $2 in
# the worktree it was started in.
function _agent {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "%s $*" >> "%s"\n' "${1}" "${LOG}"
    printf 'cat > "%s/%s.stdin"\n' "${BATS_TEST_TMPDIR}" "${1}"
    # shellcheck disable=SC2016 # expands when the stub runs
    printf 'printf "%%s\\n" "${DYAI_CREW-}" > "%s/%s.crew"\n' "${BATS_TEST_TMPDIR}" "${1}"
    printf '%s\n' "${2}"
  } > "${HOME}/.local/bin/${1}"
  chmod +x "${HOME}/.local/bin/${1}"
}

# Agent bodies.
DONE='echo work >> f.txt; printf %s "{\"status\":\"done\",\"summary\":\"added f\"}" > .dyai-result.json'
RATE='echo "Error: rate limit exceeded" >&2; exit 1'

# The first and the last task id in a `run` output, $1 (debug logging
# shares it).
ID_RE='^[0-9]{8}-[0-9]{6}-[a-z]+-[0-9a-f]{4}$'
function _first_id {
  local l
  local -a got
  mapfile -t got <<< "${1}"
  for l in "${got[@]}"; do
    if [[ "${l}" =~ ${ID_RE} ]]; then
      printf '%s\n' "${l}"
      return 0
    fi
  done
}
function _last_id {
  local i
  local -a got
  mapfile -t got <<< "${1}"
  for ((i = ${#got[@]} - 1; i >= 0; i--)); do
    if [[ "${got[i]}" =~ ${ID_RE} ]]; then
      printf '%s\n' "${got[i]}"
      return 0
    fi
  done
}

# Print the last line of $1.
function _last_line {
  local -a got
  mapfile -t got <<< "${1}"
  printf '%s\n' "${got[-1]}"
}

# Print one field of a task's state.
function _field {
  local state
  state="$(dyai_crew::get "${1}")" || return 1
  jq -r "${2}" <<< "${state}"
}

@test "run marks done from the result file" {
  _agent claude "${DONE}"
  run dyai_crew::run claude "add a line"
  assert_success
  local id
  id="$(_last_id "${output}")"
  run _field "${id}" .status
  assert_output "done"
  run git log --format=%s -1 "crew/${id}"
  assert_output "crew(claude): added f"
  run git show "crew/${id}:f.txt"
  assert_output "work"
}

@test "run sends the prompt and the contract on stdin and sets DYAI_CREW" {
  _agent claude "${DONE}"
  run dyai_crew::run claude "add a line"
  local id
  id="$(_last_id "${output}")"
  run cat "${BATS_TEST_TMPDIR}/claude.stdin"
  assert_output --partial "add a line"
  assert_output --partial ".dyai-result.json"
  run cat "${BATS_TEST_TMPDIR}/claude.crew"
  assert_output "${id}"
}

@test "run keeps a commit the agent made itself" {
  _agent claude 'echo a > a.txt; git add a.txt; git commit -qm "agent commit"; '"${DONE}"
  run dyai_crew::run claude "x"
  assert_success
  local id
  id="$(_last_id "${output}")"
  run git log --format=%s "crew/${id}"
  assert_line --index 0 "crew(claude): added f"
  assert_line --index 1 "agent commit"
}

@test "run marks failed when the agent leaves the branch" {
  _agent claude 'git checkout -q -b elsewhere; '"${DONE}"
  run dyai_crew::run claude "x"
  assert_failure
  local id
  id="$(_last_id "${output}")"
  run _field "${id}" '.status + ": " + .summary'
  assert_output "failed: agent left branch crew/${id}"
}

@test "run marks failed when exit 0 but no result file" {
  _agent claude 'echo work >> f.txt'
  run dyai_crew::run claude "x"
  assert_failure
  local last_id
  last_id="$(_last_id "${output}")"
  run _field "${last_id}" .status
  assert_output "failed"
}

@test "run marks failed when done is claimed without changes" {
  _agent claude 'printf %s "{\"status\":\"done\",\"summary\":\"nothing\"}" > .dyai-result.json'
  run dyai_crew::run claude "x"
  assert_failure
  local last_id
  last_id="$(_last_id "${output}")"
  run _field "${last_id}" '.status + ": " + .summary'
  assert_output "failed: claimed done without changes"
}

@test "a failing post_create hook stops the run" {
  _crew_config "hooks: {post_create: 'exit 4'}"
  _agent claude "${DONE}"
  run dyai_crew::run claude "x"
  assert_failure
  local last_id
  last_id="$(_last_id "${output}")"
  run _field "${last_id}" '.status + ": " + .summary'
  assert_output "failed: post_create hook failed"
  [[ ! -e "${BATS_TEST_TMPDIR}/claude.stdin" ]]
}

@test "run records the agent pid while running" {
  _agent claude 'sleep 3; '"${DONE}"
  dyai_crew::run claude "x" > "${BATS_TEST_TMPDIR}/ids" &
  local runner=$! id="" n
  for n in $(seq 1 50); do
    id="$(jq -r 'select(.status == "running") | .id' "${REPO}/.dyai/crew/tasks.jsonl" 2> /dev/null | tail -1 || true)"
    [[ -z "${id}" ]] || break
    sleep 0.1
  done
  [[ -n "${id}" ]] || fail "no running record"
  local pid start
  pid="$(_field "${id}" .pid)"
  start="$(_field "${id}" .pid_start)"
  dyai_crew::alive "${pid}" "${start}" || fail "recorded pid ${pid} is not alive"
  wait "${runner}"
}

@test "run marks timeout and kills the process group" {
  _crew_config 'timeout: 1'
  _agent claude "sleep 30 & echo \$! > ${BATS_TEST_TMPDIR}/grandchild; sleep 5"
  run dyai_crew::run claude "x"
  assert_failure
  local last_id
  last_id="$(_last_id "${output}")"
  run _field "${last_id}" .status
  assert_output "timeout"
  local gc
  gc="$(cat "${BATS_TEST_TMPDIR}/grandchild")"
  ! kill -0 "${gc}" 2> /dev/null || fail "grandchild ${gc} survived"
}

@test "auto falls back after a rate limit" {
  _crew_config 'fallback: [claude, copilot]'
  _agent claude "${RATE}"
  _agent copilot "${DONE}"
  run dyai_crew::run auto "x"
  assert_success
  local first last
  first="$(_first_id "${output}")"
  last="$(_last_id "${output}")"
  [[ "${first}" != "${last}" ]]
  run _field "${first}" '.agent + " " + .status + " " + (.worktree | tostring)'
  assert_output "claude rate_limited null"
  run _field "${last}" '.agent + " " + .status'
  assert_output "copilot done"
  [[ -s "${REPO}/.dyai/crew/cooldown/claude" ]]
  [[ ! -d "${REPO}/.worktrees/crew-${first}" ]]
  run git rev-parse --verify -q "crew/${first}"
  assert_failure
}

@test "auto falls back after an auth failure" {
  _crew_config 'fallback: [codex, copilot]'
  _agent codex "cat ${FIX}/codex.blocked.err >&2; exit 1"
  _agent copilot "${DONE}"
  run dyai_crew::run auto "x"
  assert_success
  local first
  first="$(_first_id "${output}")"
  run _field "${first}" .status
  assert_output "blocked"
}

@test "auto skips an agent in cooldown and one that is not installed" {
  _crew_config 'fallback: [gemini, claude, copilot]'
  _agent claude "${DONE}"
  _agent copilot "${DONE}"
  mkdir -p "${REPO}/.dyai/crew/cooldown"
  local now
  now="$(date +%s)"
  echo $((now + 600)) > "${REPO}/.dyai/crew/cooldown/claude"
  run dyai_crew::run auto "x"
  assert_success
  local last_id
  last_id="$(_last_id "${output}")"
  run _field "${last_id}" .agent
  assert_output "copilot"
  [[ ! -e "${BATS_TEST_TMPDIR}/claude.stdin" ]]
}

@test "run dies on an agent that is not installed" {
  run dyai_crew::run gemini "x"
  assert_failure
  assert_output --partial "gemini is not installed"
}

@test "run from inside a worktree creates under the main checkout" {
  _agent claude "${DONE}"
  git worktree add -q "${REPO}/.worktrees/side" -b side
  cd "${REPO}/.worktrees/side"
  run dyai_crew::run claude "x"
  assert_success
  local id
  id="$(_last_id "${output}")"
  run _field "${id}" .worktree
  assert_output "${REPO}/.worktrees/crew-${id}"
}

@test "run with a plan passes it to the agent and records it" {
  _agent claude "${DONE}"
  printf '1. touch f.txt\n' > "${BATS_TEST_TMPDIR}/plan.md"
  run dyai_crew::run claude "x" "${BATS_TEST_TMPDIR}/plan.md"
  local id
  id="$(_last_id "${output}")"
  run cat "${BATS_TEST_TMPDIR}/claude.stdin"
  assert_output --partial "## Plan to follow"
  assert_output --partial "1. touch f.txt"
  run _field "${id}" .plan
  assert_output "${REPO}/.dyai/crew/${id}.plan.md"
}

@test "run detach returns before the agent finishes" {
  _agent claude 'sleep 2; '"${DONE}"
  local start=${SECONDS}
  run dyai_crew::run claude "x" "" detach
  assert_success
  ((SECONDS - start < 2)) || fail "detach waited"
  local id n st
  id="$(_last_id "${output}")"
  for n in $(seq 1 60); do
    st="$(_field "${id}" .status)"
    [[ "${st}" != "done" ]] || break
    sleep 0.1
  done
  run _field "${id}" .status
  assert_output "done"
}

@test "two runs in the same second get different ids" {
  _agent claude "${DONE}"
  dyai_crew::run claude "a" > "${BATS_TEST_TMPDIR}/a" &
  dyai_crew::run claude "b" > "${BATS_TEST_TMPDIR}/b" &
  wait
  local a b
  a="$(tail -1 "${BATS_TEST_TMPDIR}/a")"
  b="$(tail -1 "${BATS_TEST_TMPDIR}/b")"
  [[ -n "${a}" && -n "${b}" && "${a}" != "${b}" ]] || fail "ids: ${a} ${b}"
  [[ "${a}" =~ ^[0-9]{8}-[0-9]{6}-claude-[0-9a-f]{4}$ ]]
}

# shellcheck disable=SC2030 # bats run sets output in this shell
@test "run warns when the checkout has uncommitted changes" {
  _agent claude "${DONE}"
  echo dirty > dirty.txt
  run dyai_crew::run claude "x"
  assert_output --partial "uncommitted"
}

# Reviewer stubs that answer with a verdict in each agent's own envelope.
function _reviewers {
  _agent copilot "cat ${FIX}/copilot.verdict.out"
  _agent gemini "cat ${FIX}/gemini.verdict.out"
  _agent opencode "cat ${FIX}/opencode.verdict.out"
  # shellcheck disable=SC2016 # expands when the stub runs
  _agent codex 'while (($# > 0)); do [[ "$1" != -o ]] || cp '"${FIX}"'/codex.verdict.last "$2"; shift; done'
}

# A copilot answer carrying verdict $1.
function _copilot_says {
  local line
  line="$(jq -cn --arg v "${1}" '{type: "assistant.message", data: {content: ({verdict: $v, findings: []} | tojson)}}')"
  _agent copilot "printf '%s\\n' '${line}'"
}

# Run a done claude task; its id lands in TASK_ID.
function _done_task {
  _agent claude "${DONE}"
  run dyai_crew::run claude "add a line"
  assert_success
  # shellcheck disable=SC2031 # bats run sets output in this shell
  TASK_ID="$(_last_id "${output}")"
}

@test "review uses the configured cross reviewer, read-only, with the diff on stdin" {
  local id
  _done_task
  id="${TASK_ID}"
  _crew_config 'reviewer: {claude: copilot}'
  _copilot_says pass
  run dyai_crew::review "${id}"
  assert_success
  run grep '^copilot' "${LOG}"
  assert_output --partial "--deny-tool shell --deny-tool write"
  run cat "${BATS_TEST_TMPDIR}/copilot.stdin"
  assert_output --partial "+work"
  assert_output --partial "add a line"
}

@test "review refuses the same agent" {
  local id
  _done_task
  id="${TASK_ID}"
  run dyai_crew::review "${id}" claude
  assert_failure
  assert_output --partial "the writer"
}

@test "review parses the verdict from each agent's envelope" {
  local id head a
  _done_task
  id="${TASK_ID}"
  head="$(git rev-parse "crew/${id}")"
  _reviewers
  for a in copilot gemini opencode codex; do
    run dyai_crew::review "${id}" "${a}"
    assert_success
    run _field "${id}" '.verdict + " " + .reviewer + " " + .reviewed_sha'
    assert_output "pass ${a} ${head}"
  done
  # And claude as the reviewer, through its stream-json envelope.
  _agent copilot "${DONE}"
  run dyai_crew::run copilot "x"
  local other
  other="$(_last_id "${output}")"
  _agent claude "cat ${FIX}/claude.verdict.out"
  run dyai_crew::review "${other}" claude
  run _field "${other}" .verdict
  assert_output "pass"
}

@test "review writes the answer to a review file and prints its path" {
  local id
  _done_task
  id="${TASK_ID}"
  _copilot_says pass
  run dyai_crew::review "${id}" copilot
  local path
  path="$(_last_line "${output}")"
  [[ "${path}" == "${REPO}/.dyai/crew/${id}.review.md" ]] || fail "${path}"
  grep -q '"verdict":"pass"' "${path}"
}

@test "review records unknown for prose output" {
  local id
  _done_task
  id="${TASK_ID}"
  _agent copilot "printf '%s\\n' '{\"type\":\"assistant.message\",\"data\":{\"content\":\"LGTM\"}}'"
  run dyai_crew::review "${id}" copilot
  run _field "${id}" .verdict
  assert_output "unknown"
}

@test "review records unknown when the reviewer is rate limited" {
  local id
  _done_task
  id="${TASK_ID}"
  _agent copilot "${RATE}"
  run dyai_crew::review "${id}" copilot
  run _field "${id}" '.verdict + ": " + .review_summary'
  assert_output "unknown: rate_limited"
}

@test "review hands a large diff over as a file" {
  _agent claude 'head -c 307200 /dev/zero | tr "\\0" a > big.txt; '"${DONE}"
  run dyai_crew::run claude "big"
  local id
  id="$(_last_id "${output}")"
  _copilot_says pass
  run dyai_crew::review "${id}" copilot
  assert_success
  local size
  size="$(wc -c < "${BATS_TEST_TMPDIR}/copilot.stdin")"
  ((size < 102400)) || fail "prompt is ${size} bytes"
  grep -q '.dyai-review.diff' "${BATS_TEST_TMPDIR}/copilot.stdin"
  [[ -s "${REPO}/.worktrees/crew-${id}/.dyai-review.diff" ]]
}

@test "review sends the plan when the task has one" {
  _agent claude "${DONE}"
  printf '1. touch f.txt\n' > "${BATS_TEST_TMPDIR}/plan.md"
  run dyai_crew::run claude "x" "${BATS_TEST_TMPDIR}/plan.md"
  local id
  id="$(_last_id "${output}")"
  _copilot_says pass
  run dyai_crew::review "${id}" copilot
  run cat "${BATS_TEST_TMPDIR}/copilot.stdin"
  assert_output --partial "1. touch f.txt"
  assert_output --partial "plan_drift"
}

@test "fix reruns the writer with the review and clears the verdict" {
  local id before
  _done_task
  id="${TASK_ID}"
  _copilot_says fail
  run dyai_crew::review "${id}" copilot
  before="$(git rev-list --count "crew/${id}")"
  _agent claude 'echo more >> f.txt; printf %s "{\"status\":\"done\",\"summary\":\"fixed\"}" > .dyai-result.json'
  run dyai_crew::fix "${id}"
  assert_success
  run cat "${BATS_TEST_TMPDIR}/claude.stdin"
  assert_output --partial '"verdict":"fail"'
  run git rev-list --count "crew/${id}"
  assert_output "$((before + 1))"
  run _field "${id}" '(.verdict | tostring) + " " + (.reviewed_sha | tostring) + " " + .status'
  assert_output "null null done"
}

@test "fix refuses unless the verdict is fail" {
  local id
  _done_task
  id="${TASK_ID}"
  run dyai_crew::fix "${id}"
  assert_failure
  _copilot_says pass
  run dyai_crew::review "${id}" copilot
  run dyai_crew::fix "${id}"
  assert_failure
}

@test "review detach returns at once and records the verdict later" {
  local id n st
  _done_task
  id="${TASK_ID}"
  _agent copilot "sleep 1; cat ${FIX}/copilot.verdict.out"
  run dyai_crew::review "${id}" copilot detach
  assert_success
  for n in $(seq 1 60); do
    st="$(_field "${id}" '.verdict // ""')"
    [[ -z "${st}" ]] || break
    sleep 0.1
  done
  assert_equal "${st}" "pass"
}

# A done claude task with a pass verdict on its head, merged from branch
# `integrate`; its id lands in TASK_ID.
function _passed_task {
  git checkout -q -b integrate
  _done_task
  _copilot_says pass
  run dyai_crew::review "${TASK_ID}" copilot
  assert_success
}

@test "merge commits a done task and cleans up" {
  _passed_task
  local id="${TASK_ID}"
  run dyai_crew::merge "${id}"
  assert_success
  run git log --format=%s -1
  assert_output "merge(crew): ${id}"
  run git show HEAD:f.txt
  assert_output "work"
  [[ ! -d "${REPO}/.worktrees/crew-${id}" ]]
  run git rev-parse --verify -q "crew/${id}"
  assert_failure
  run _field "${id}" .status
  assert_output "merged"
}

@test "merge aborts on conflict and records it" {
  _passed_task
  local id="${TASK_ID}"
  echo mine > f.txt
  git add f.txt
  git commit -qm "conflicting"
  run dyai_crew::merge "${id}"
  assert_failure
  run _field "${id}" .status
  assert_output "conflict"
  run git status --porcelain
  assert_output ""
  run cat f.txt
  assert_output "mine"
}

@test "merge aborts when the gate fails" {
  _passed_task
  local id="${TASK_ID}"
  _crew_config "gate: 'echo gate said no; false'"
  run dyai_crew::merge "${id}"
  assert_failure
  run _field "${id}" '.status + ": " + .summary'
  assert_output "gate_failed: gate said no"
  run git status --porcelain
  assert_output ""
}

@test "merge runs the gate on the merged tree" {
  _passed_task
  _crew_config "gate: 'test -f f.txt'"
  run dyai_crew::merge "${TASK_ID}"
  assert_success
}

@test "merge refuses on main" {
  _done_task
  run dyai_crew::merge "${TASK_ID}"
  assert_failure
  assert_output --partial "integration branch"
}

@test "merge refuses a dirty tree" {
  _passed_task
  echo dirty > dirty.txt
  run dyai_crew::merge "${TASK_ID}"
  assert_failure
  assert_output --partial "uncommitted"
  [[ -d "${REPO}/.worktrees/crew-${TASK_ID}" ]]
}

@test "merge refuses without a pass verdict" {
  git checkout -q -b integrate
  _done_task
  local id="${TASK_ID}"
  run dyai_crew::merge "${id}"
  assert_failure
  assert_output --partial "pass verdict"
  _copilot_says fail
  dyai_crew::review "${id}" copilot > /dev/null
  run dyai_crew::merge "${id}"
  assert_failure
  _agent copilot "printf '%s\\n' '{\"type\":\"assistant.message\",\"data\":{\"content\":\"LGTM\"}}'"
  dyai_crew::review "${id}" copilot > /dev/null
  run dyai_crew::merge "${id}"
  assert_failure
}

@test "merge refuses when the branch moved after review" {
  _passed_task
  local id="${TASK_ID}"
  git -C "${REPO}/.worktrees/crew-${id}" commit -q --allow-empty -m "after review"
  run dyai_crew::merge "${id}"
  assert_failure
  assert_output --partial "moved"
}

@test "merge skips the review check when require_review is false" {
  git checkout -q -b integrate
  _done_task
  _crew_config 'require_review: false'
  run dyai_crew::merge "${TASK_ID}"
  assert_success
}

@test "merge stops at a fenced path" {
  git checkout -q -b integrate
  _agent claude 'mkdir -p secrets; echo s > secrets/x; '"${DONE}"
  run dyai_crew::run claude "x"
  local id
  id="$(_last_id "${output}")"
  _crew_config "require_review: false"
  run dyai_crew::merge "${id}"
  assert_failure
  run _field "${id}" '.status + ": " + .summary'
  assert_output "needs_human: secrets/x"
  run git log --format=%s -1
  assert_output "init"
  run git status --porcelain
  assert_output ""
}

@test "a glob fence matches at the repository root" {
  git checkout -q -b integrate
  _agent claude 'echo k > x.age; '"${DONE}"
  run dyai_crew::run claude "x"
  local id
  id="$(_last_id "${output}")"
  _crew_config "{require_review: false, fences: [':(glob)**/*.age']}"
  run dyai_crew::merge "${id}"
  assert_failure
  run _field "${id}" .status
  assert_output "needs_human"
}

@test "drop keeps an unmerged branch and says so" {
  _done_task
  local id="${TASK_ID}"
  run dyai_crew::drop "${id}"
  assert_success
  assert_output --partial "kept branch crew/${id}"
  [[ ! -d "${REPO}/.worktrees/crew-${id}" ]]
  git rev-parse --verify -q "crew/${id}" > /dev/null
  run _field "${id}" .status
  assert_output "dropped"
}

@test "drop finished leaves done and running tasks alone" {
  _done_task
  local done_id="${TASK_ID}"
  _agent claude 'echo work >> f.txt; printf %s "{\"status\":\"partial\",\"summary\":\"half\"}" > .dyai-result.json'
  run dyai_crew::run claude "x"
  local partial_id
  partial_id="$(_last_id "${output}")"
  run dyai_crew::drop finished
  assert_success
  run _field "${partial_id}" .status
  assert_output "dropped"
  run _field "${done_id}" .status
  assert_output "done"
  [[ -d "${REPO}/.worktrees/crew-${done_id}" ]]
}
