# dyshellint disable=SC2154 DOTFILES_DIR, HOME and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/dyai.sh"
  . "${DOTFILES_DIR}/scripts/lib/dyai_crew.sh"
  FIX="${DOTFILES_DIR}/scripts/test/fixtures/crew"
  LOG="${BATS_TEST_TMPDIR}/calls"
  REPO="${BATS_TEST_TMPDIR}/repo"
  # dyshellint disable=BSG062 test_helper, loaded above, unsets GIT_DIR and its kin
  git init -q "${REPO}"
  git -C "${REPO}" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
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
