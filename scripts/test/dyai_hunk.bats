# dyshellint disable=SC2154 DOTFILES_DIR, HOME and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/dyai_zellij.sh"
  . "${DOTFILES_DIR}/scripts/lib/dyai_hunk.sh"
  LOG="${BATS_TEST_TMPDIR}/calls"
  REPO="${BATS_TEST_TMPDIR}/repo"
  # dyshellint disable=BSG062 test_helper, loaded above, unsets GIT_DIR and its kin
  git init -q "${REPO}"
  # git reports the resolved path: macOS temp dirs sit behind a /private symlink.
  REPO="$(cd "${REPO}" && pwd -P)"
  NOTES="${REPO}/.git/dyai-hunk.json"
  HUNK_CMD="hunk diff --watch --agent-context ${NOTES}"
  unset ZELLIJ KITTY_LISTEN_ON DYAI_VIEWS
  # hunk: `session get` succeeds only when HUNK_LIVE=1.
  # shellcheck disable=SC2016 # the stub body expands at its own run time
  _stub hunk '[[ "$1 $2" != "session get" ]] || [[ "${HUNK_LIVE-}" == 1 ]]'
  _stub kitty true
  _stub zellij true
}

# Write a stub $1 on PATH that logs its arguments, then runs $2.
function _stub {
  printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\n%s\n' "${1}" "${LOG}" "${2}" \
    > "${HOME}/.local/bin/${1}"
  chmod +x "${HOME}/.local/bin/${1}"
}

# Print the terminal launches the stubs logged.
function _launches {
  grep -E '^(kitty|zellij) ' "${LOG}" 2> /dev/null || true
}

@test "dyai-hunk falls back to a kitty tab without zellij" {
  _stub zellij "exit 127"
  touch "${REPO}/new"
  cd "${REPO}" && KITTY_LISTEN_ON=unix:/tmp/kitty-test run dyai_hunk::main
  assert_success
  run grep '^kitty ' "${LOG}"
  assert_output "kitty @ launch --type=tab --keep-focus --cwd=${REPO} ${HUNK_CMD}"
}

@test "dyai-hunk prefers a zellij floating pane inside zellij" {
  touch "${REPO}/new"
  cd "${REPO}" && KITTY_LISTEN_ON=unix:/tmp/kitty-test ZELLIJ=0 run dyai_hunk::main
  assert_success
  local got
  got="$(_launches)"
  [[ "${got}" == "zellij run --floating --name hunk --cwd ${REPO} --close-on-exit -- ${HUNK_CMD}" ]] \
    || fail "${got}"
}

@test "dyai-hunk outside zellij opens hunk in the background dyai session" {
  touch "${REPO}/new"
  cd "${REPO}" && run dyai_hunk::main
  assert_success
  run grep -c -- "zellij --session dyai run --name hunk --cwd ${REPO} --close-on-exit -- ${HUNK_CMD}" "${LOG}"
  assert_output 1
}

@test "dyai-hunk creates an empty notes sidecar but keeps an agent's own" {
  touch "${REPO}/new"
  cd "${REPO}" && KITTY_LISTEN_ON=unix:/tmp/kitty-test run dyai_hunk::main
  run cat "${NOTES}"
  [[ "${output}" == '{}' ]]
  echo '{"files":[]}' > "${NOTES}"
  KITTY_LISTEN_ON=unix:/tmp/kitty-test run dyai_hunk::main
  run cat "${NOTES}"
  [[ "${output}" == '{"files":[]}' ]]
}

@test "dyai-hunk opens nothing on a clean checkout, outside git, or with a live session" {
  cd "${REPO}" && KITTY_LISTEN_ON=unix:/tmp/kitty-test run dyai_hunk::main
  assert_success
  cd "${BATS_TEST_TMPDIR}" && KITTY_LISTEN_ON=unix:/tmp/kitty-test run dyai_hunk::main
  assert_success
  touch "${REPO}/new"
  cd "${REPO}" && KITTY_LISTEN_ON=unix:/tmp/kitty-test HUNK_LIVE=1 run dyai_hunk::main
  assert_success
  local got
  got="$(_launches)"
  [[ -z "${got}" ]]
}

@test "dyai-hunk never fails, even when the launcher does or no terminal is known" {
  touch "${REPO}/new"
  cd "${REPO}" && run dyai_hunk::main
  assert_success
  _stub kitty false
  KITTY_LISTEN_ON=unix:/tmp/kitty-test run dyai_hunk::main
  assert_success
}

@test "dyai-hunk does nothing inside a crew task" {
  touch "${REPO}/new"
  cd "${REPO}" && ZELLIJ=0 DYAI_CREW=20261026-000000-claude-abcd run dyai_hunk::main
  assert_success
  run _launches
  assert_output ""
}
