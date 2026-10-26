setup() {
  load test_helper
  setup_dotfiles_test_env
  # shellcheck disable=SC2154 # DOTFILES_DIR is set by test_helper.bash
  . "${DOTFILES_DIR}/scripts/lib/mcp_share.sh"
  STATE="${HOME}/.local/state/demo"
}

teardown() {
  [[ -f "${STATE}/serve.pid" ]] && kill "$(< "${STATE}/serve.pid")" 2> /dev/null || true
}

# The backend counts as up once its ready file exists.
function _probe {
  local deadline=$((SECONDS + $1))
  until [[ -f "${HOME}/ready" ]]; do
    ((SECONDS < deadline)) || return 1
    sleep 0.1
  done
}

# Arguments: seconds to wait before it is ready, then the log file.
function _serve {
  echo start >> "${HOME}/starts"
  sleep "$1"
  touch "${HOME}/ready"
  exec < /dev/null &>> "$2"
  exec sleep 60
}

@test "mcp_share starts one backend for every caller" {
  run mcp_share::ensure_server "${STATE}" 5 _probe _serve 0
  assert_success
  run mcp_share::ensure_server "${STATE}" 5 _probe _serve 0
  assert_success
  run cat "${HOME}/starts"
  assert_output start
  run stat -c %a "${STATE}"
  assert_output 700
}

@test "mcp_share counts a backend still starting as up and starts no second one" {
  run mcp_share::ensure_server "${STATE}" 1 _probe _serve 3
  assert_success
  run mcp_share::ensure_server "${STATE}" 1 _probe _serve 3
  assert_success
  run cat "${HOME}/starts"
  assert_output start
}

@test "mcp_share fails when the backend dies before it answers" {
  function _crash { echo start >> "${HOME}/starts"; }
  run mcp_share::ensure_server "${STATE}" 1 _probe _crash
  assert_failure
}
