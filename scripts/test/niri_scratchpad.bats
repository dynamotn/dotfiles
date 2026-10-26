#!/usr/bin/env bats
# dyshellint disable=SC2154 DOTFILES_DIR, HOME and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/niri_scratchpad.sh"
  LOG="${BATS_TEST_TMPDIR}/calls"
  WINDOWS="${BATS_TEST_TMPDIR}/windows.json"
  echo '[{"id":7,"app_id":"kitty","is_focused":true}]' > "${WINDOWS}"
  # niri: `msg -j windows` and `msg -j workspaces` print the fixtures, every
  # other call is logged.
  cat > "${HOME}/.local/bin/niri" << EOF
#!/usr/bin/env bash
case "\$*" in
  "msg -j windows") cat "${WINDOWS}" ;;
  "msg -j workspaces") echo '[{"idx":1,"is_focused":false},{"idx":3,"is_focused":true}]' ;;
  *) echo "\$*" >> "${LOG}" ;;
esac
EOF
  chmod +x "${HOME}/.local/bin/niri"
}

@test "niri_scratchpad::toggle starts the app when no window of it exists" {
  run niri_scratchpad::toggle btop kitty --class btop
  assert_success
  run cat "${LOG}"
  assert_output "msg action spawn -- kitty --class btop"
}

@test "niri_scratchpad::toggle hides the focused window on the scratchpad workspace" {
  echo '[{"id":7,"app_id":"kitty","is_focused":false},{"id":9,"app_id":"btop","is_focused":true}]' > "${WINDOWS}"
  run niri_scratchpad::toggle btop kitty --class btop
  assert_success
  run cat "${LOG}"
  assert_output "msg action move-window-to-workspace --window-id 9 --focus false scratchpad"
}

@test "niri_scratchpad::toggle pulls an unfocused window to the focused workspace" {
  echo '[{"id":7,"app_id":"kitty","is_focused":true},{"id":9,"app_id":"btop","is_focused":false}]' > "${WINDOWS}"
  run niri_scratchpad::toggle btop kitty --class btop
  assert_success
  run cat "${LOG}"
  assert_output "msg action move-window-to-workspace --window-id 9 --focus false 3
msg action focus-window --id 9"
}
