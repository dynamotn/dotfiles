# dyshellint disable=SC2154 DOTFILES_DIR, HOME and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/dyai_zellij.sh"
  LOG="${BATS_TEST_TMPDIR}/calls"
  unset ZELLIJ KITTY_LISTEN_ON DYAI_VIEWS
  # zellij: `action list-clients` lists one client only when ZELLIJ_CLIENTS=1.
  # shellcheck disable=SC2016 # the stub body expands at its own run time
  _stub zellij 'if [[ "$*" == *"list-clients"* ]]; then
  echo "CLIENT_ID ZELLIJ_PANE_ID RUNNING_COMMAND"
  [[ "${ZELLIJ_CLIENTS-}" != 1 ]] || echo "1 terminal_0 fish"
fi'
  _stub kitty true
}

# Write a stub $1 on PATH that logs its arguments, then runs $2.
function _stub {
  printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\n%s\n' "${1}" "${LOG}" "${2}" \
    > "${HOME}/.local/bin/${1}"
  chmod +x "${HOME}/.local/bin/${1}"
}

@test "open floats a pane inside zellij and closes it on exit" {
  ZELLIJ=0 run dyai_zellij::open hunk /repo -- hunk diff --watch
  assert_success
  run cat "${LOG}"
  assert_output "zellij run --floating --name hunk --cwd /repo --close-on-exit -- hunk diff --watch"
}

@test "open keep leaves the pane open after the command ends" {
  ZELLIJ=0 run dyai_zellij::open crew-x /repo keep -- dyai logs x --follow
  assert_success
  run cat "${LOG}"
  assert_output "zellij run --floating --name crew-x --cwd /repo -- dyai logs x --follow"
}

@test "open outside zellij uses the background dyai session and shows it in kitty" {
  KITTY_LISTEN_ON=unix:/tmp/k run dyai_zellij::open hunk /repo -- hunk diff --watch
  assert_success
  run cat "${LOG}"
  assert_line --index 0 "zellij attach --create-background dyai"
  assert_line --index 1 "zellij --session dyai run --name hunk --cwd /repo --close-on-exit -- hunk diff --watch"
  assert_line --index 2 "zellij --session dyai action list-clients"
  assert_line --index 3 "kitty @ launch --type=tab --keep-focus zellij attach dyai"
}

@test "open adds no kitty tab when a client already shows the dyai session" {
  KITTY_LISTEN_ON=unix:/tmp/k ZELLIJ_CLIENTS=1 run dyai_zellij::open hunk /repo -- hunk diff
  assert_success
  run grep -c '^kitty' "${LOG}"
  assert_output 0
}

@test "open falls back to a kitty tab running the command when zellij fails" {
  _stub zellij "exit 127"
  KITTY_LISTEN_ON=unix:/tmp/k run dyai_zellij::open hunk /repo -- hunk diff --watch
  assert_success
  run grep '^kitty' "${LOG}"
  assert_output "kitty @ launch --type=tab --keep-focus --cwd=/repo hunk diff --watch"
}

@test "open does nothing with DYAI_VIEWS=off" {
  ZELLIJ=0 DYAI_VIEWS=off run dyai_zellij::open hunk /repo -- hunk diff
  assert_failure
  [[ ! -e "${LOG}" ]]
}

@test "open fails when neither zellij nor kitty can show it" {
  _stub zellij "exit 127"
  run dyai_zellij::open hunk /repo -- hunk diff
  assert_failure
}
