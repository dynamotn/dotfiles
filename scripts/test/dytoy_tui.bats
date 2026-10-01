setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/dytoy.sh"
  . "${DOTFILES_DIR}/scripts/lib/dytoy_tui.sh"
  DYTOY_METHODS=(os binary mise shell)
  export SYNC_REPO="false"
  # The buffer is sized from the environment rather than from a terminal, so
  # the drawing assertions do not depend on the machine running the suite.
  export COLUMNS=100 LINES=16
  export NO_COLOR=1
  DYBATPHO_SCREEN_WIDTH=0
  DYBATPHO_SCREEN_HEIGHT=0
  dybatpho::screen_size || true
  dybatpho::screen_clear

  write_tools_yaml << 'EOF'
- name: shelltool
  method: shell
- name: pkg
  method: os
  is_essential: true
- name: present
  method: binary
- name: missing
  method: binary
  is_essential: true
- name: off
  method: mise
  enabled: false
EOF
  printf '#!/bin/sh\n' > "${HOME}/.local/bin/present"
  chmod +x "${HOME}/.local/bin/present"
}

# Print one row of the buffer with its styles stripped.
function screen_row {
  local rendered
  __dybatpho_screen_render_into rendered "$1"
  printf '%s' "${rendered}" | LC_ALL=C sed -E 's/\x1B\[[0-9;]*m//g'
}

# Print the whole buffer with its styles stripped.
function screen_dump {
  local row
  for ((row = 0; row < DYBATPHO_SCREEN_HEIGHT; row++)); do
    screen_row "${row}"
    printf '\n'
  done
}

# Write a stand-in for the dytoy executable: it logs its arguments and fails
# for the tool named `missing`.
function write_fake_self {
  DYTOY_TUI_SELF="${BATS_TEST_TMPDIR}/fake-dytoy"
  cat > "${DYTOY_TUI_SELF}" << 'EOF'
#!/usr/bin/env bash
printf 'args: %s\n' "$*"
printf '\033[1;32mcoloured\033[0m\n'
[[ "$*" != *"--tool missing"* ]]
EOF
  chmod +x "${DYTOY_TUI_SELF}"
  DYTOY_TUI_LOG_DIR="${BATS_TEST_TMPDIR}/logs"
  dybatpho::ensure_dir "${DYTOY_TUI_LOG_DIR}" > /dev/null
}

# Pick the tools at the given indexes, as the space key would.
function pick_tools {
  local index
  for index in "$@"; do
    DYTOY_TUI_PICKED[index]=true
  done
}

# Poll the install phase until it ends, failing the test if it never does.
function run_until_done {
  local tries=0
  while [[ "${DYTOY_TUI_PHASE}" == "install" ]] && ((tries < 200)); do
    dytoy_tui::poll
    sleep 0.05
    tries=$((tries + 1))
  done
  assert_equal "${DYTOY_TUI_PHASE}" "done"
}

@test "dytoy_tui::has_terminal refuses a run without a terminal" {
  run dytoy_tui::has_terminal < /dev/null
  assert_failure
}

@test "dytoy_tui::load_tools lists enabled tools in method order" {
  dytoy_tui::load_tools
  assert_equal "${DYTOY_TUI_NAME[*]}" "pkg present missing shelltool"
  assert_equal "${DYTOY_TUI_METHOD[*]}" "os binary binary shell"
  assert_equal "${DYTOY_TUI_ESSENTIAL[*]}" "true false true false"
  assert_equal "${DYTOY_TUI_INSTALLED[*]}" "unknown yes no no"
}

@test "dytoy_tui::load_tools starts with nothing picked" {
  dytoy_tui::load_tools
  assert_equal "${DYTOY_TUI_PICKED[*]}" "false false false false"

  export ONLY_NOT_INSTALLED="false"
  dytoy_tui::load_tools
  assert_equal "${DYTOY_TUI_PICKED[*]}" "false false false false"
}

@test "dytoy_tui::load_tools keeps only essential tools when asked" {
  export ONLY_ESSENTIAL="true"
  dytoy_tui::load_tools
  assert_equal "${DYTOY_TUI_NAME[*]}" "pkg missing"
}

@test "dytoy_tui::child_args passes the run options down to the child" {
  dytoy_tui::load_tools
  local -a args=()
  export DRY_RUN="true" ONLY_NOT_INSTALLED="false" LOG_LEVEL="warn"
  dytoy_tui::child_args args 0 true
  assert_equal "${args[*]}" "os --tool pkg --log-level warn --dry-run --no-check-installed --sync"

  export DRY_RUN="false" ONLY_NOT_INSTALLED="true" ONLY_ESSENTIAL="true" LIST_CONTENTS="true"
  dytoy_tui::child_args args 2 false
  assert_equal "${args[*]}" "binary --tool missing --log-level warn --essential --check-installed --list"
}

@test "dytoy_tui::log_tail strips escapes and keeps what a redrawn line ended as" {
  local log="${BATS_TEST_TMPDIR}/sample.log"
  printf 'first\n\033[1;31mred\033[0m\n10%%\r50%%\r100%%\nwin\r\nlast\tline\n' > "${log}"
  local -a lines=()
  dytoy_tui::log_tail lines "${log}" 4
  assert_equal "${#lines[@]}" 4
  assert_equal "${lines[0]}" "red"
  assert_equal "${lines[1]}" "100%"
  assert_equal "${lines[2]}" "win"
  assert_equal "${lines[3]}" "last  line"

  dytoy_tui::log_tail lines "${BATS_TEST_TMPDIR}/absent.log" 4
  assert_equal "${#lines[@]}" 0
}

@test "dytoy_tui::handle_pick_key toggles, picks a whole tab and switches tabs" {
  dytoy_tui::load_tools
  DYTOY_TUI_TAB=1

  # Space toggles the tool under the cursor and moves on to the next one.
  dytoy_tui::handle_pick_key space
  assert_equal "${DYTOY_TUI_PICKED[1]}" "true"
  assert_equal "${DYTOY_TUI_CURSOR[binary]}" "1"
  dytoy_tui::handle_pick_key space
  assert_equal "${DYTOY_TUI_PICKED[2]}" "true"
  dytoy_tui::handle_pick_key space
  assert_equal "${DYTOY_TUI_PICKED[1]}" "false"

  # `a` picks the whole tab, and clears it once it is fully picked.
  dytoy_tui::handle_pick_key char:a
  assert_equal "${DYTOY_TUI_PICKED[1]} ${DYTOY_TUI_PICKED[2]}" "true true"
  dytoy_tui::handle_pick_key char:a
  assert_equal "${DYTOY_TUI_PICKED[1]} ${DYTOY_TUI_PICKED[2]}" "false false"

  dytoy_tui::handle_pick_key left
  dytoy_tui::handle_pick_key left
  assert_equal "${DYTOY_TUI_TAB}" "3"
  dytoy_tui::handle_pick_key tab
  assert_equal "${DYTOY_TUI_TAB}" "0"
}

@test "dytoy_tui::handle_pick_key starts installing only when something is picked" {
  dytoy_tui::load_tools
  dytoy_tui::handle_pick_key enter
  assert_equal "${DYTOY_TUI_PHASE}" "pick"
  assert_equal "${DYTOY_TUI_STATUS}" "Nothing picked: press space to pick a tool"

  DYTOY_TUI_PICKED[3]=true
  dytoy_tui::handle_pick_key enter
  assert_equal "${DYTOY_TUI_PHASE}" "install"

  dytoy_tui::handle_pick_key char:q
  assert_equal "${DYTOY_TUI_RUNNING}" "false"
}

@test "dytoy_tui::poll installs the queue in order and records each outcome" {
  dytoy_tui::load_tools
  export SYNC_REPO="true"
  write_fake_self
  pick_tools 0 2 3
  dytoy_tui::build_queue
  assert_equal "${DYTOY_TUI_QUEUE[*]}" "0 2 3"
  DYTOY_TUI_PHASE="install"
  run_until_done

  assert_equal "${DYTOY_TUI_STATE[0]} ${DYTOY_TUI_STATE[2]} ${DYTOY_TUI_STATE[3]}" "ok failed ok"
  assert_equal "${DYTOY_TUI_STATE[1]}" "pending"
  run cat "${DYTOY_TUI_LOG[0]}"
  assert_output --partial "args: os --tool pkg"
  # The repositories are synced by the first package manager tool only.
  assert_output --partial "--sync"
  run cat "${DYTOY_TUI_LOG[2]}"
  assert_output --partial "[exit status 1]"

  dytoy_tui::summary 2> /dev/null
  assert_equal "${DYTOY_TUI_FAILED}" "true"
}

@test "dytoy_tui::stop ends the running tool and skips the rest" {
  dytoy_tui::load_tools
  write_fake_self
  printf '#!/usr/bin/env bash\nsleep 30\n' > "${DYTOY_TUI_SELF}"
  pick_tools 0 2 3
  dytoy_tui::build_queue
  DYTOY_TUI_PHASE="install"
  dytoy_tui::poll
  assert_equal "${DYTOY_TUI_STATE[0]}" "running"

  dytoy_tui::stop
  assert_equal "${DYTOY_TUI_PHASE}" "done"
  assert_equal "${DYTOY_TUI_PID}" ""
  assert_equal "${DYTOY_TUI_STATE[0]} ${DYTOY_TUI_STATE[2]} ${DYTOY_TUI_STATE[3]}" "failed skipped skipped"
}

@test "dytoy_tui::handle_install_key asks before stopping and quits once done" {
  dytoy_tui::load_tools
  pick_tools 0 2 3
  dytoy_tui::build_queue
  DYTOY_TUI_PHASE="install"

  dytoy_tui::handle_install_key char:q
  assert_equal "${DYTOY_TUI_MODE}" "confirm"
  # Anything but `y` keeps going.
  dytoy_tui::handle_install_key enter
  assert_equal "${DYTOY_TUI_MODE}" "normal"
  assert_equal "${DYTOY_TUI_PHASE}" "install"

  dytoy_tui::handle_install_key down
  assert_equal "${DYTOY_TUI_VIEW}" "1"
  assert_equal "${DYTOY_TUI_FOLLOW}" "false"

  DYTOY_TUI_PHASE="done"
  dytoy_tui::handle_install_key char:q
  assert_equal "${DYTOY_TUI_RUNNING}" "false"
}

@test "dytoy_tui::draw_pick shows tabs, checkboxes and the tool's YAML" {
  dytoy_tui::load_tools
  DYTOY_TUI_TAB=1
  dytoy_tui::draw
  run screen_dump
  assert_output --partial "os 0/1"
  assert_output --partial "binary 0/2"
  assert_output --partial "[ ] ✓ present"
  assert_output --partial "[ ] · missing ★"
  assert_output --partial "method: binary"
  assert_output --partial "0 picked"
}

@test "dytoy_tui::draw_install shows progress, states and the followed log" {
  dytoy_tui::load_tools
  write_fake_self
  pick_tools 0 2 3
  dytoy_tui::build_queue
  DYTOY_TUI_PHASE="install"
  run_until_done
  dytoy_tui::draw
  run screen_dump
  assert_output --partial "Finished"
  assert_output --partial "2 installed, 1 failed, 0 skipped"
  assert_output --partial "✓ os/pkg"
  assert_output --partial "✗ binary/missing"
  assert_output --partial "Log: shelltool"
  assert_output --partial "coloured"
}
