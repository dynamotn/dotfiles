setup() {
  load test_helper
  setup_dotfiles_test_env
  # shellcheck disable=SC2154 # DOTFILES_DIR is set by test_helper.bash
  . "${DOTFILES_DIR}/scripts/lib/laya_mcp.sh"
  export LAYA_SHARED_PORT=$((40000 + RANDOM % 20000))
  export LAYA_MCP_WAIT=10
  # laya-serve stub: records its environment, then listens like the real one.
  cat > "${HOME}/.local/bin/laya-serve" << 'EOF'
#!/usr/bin/env bash
env | grep '^LAYA_' | sort > "${HOME}/serve.env"
echo start >> "${HOME}/serve.starts"
exec python3 -m http.server "${LAYA_PORT}" --bind "${LAYA_HOST}"
EOF
  # laya-mcp-server stub: prints how it was started instead of speaking MCP.
  cat > "${HOME}/.local/bin/laya-mcp-server" << 'EOF'
#!/usr/bin/env bash
echo "base=${LAYA_BASE_URL-} preload=${LAYA_PRELOAD-} args=$*"
EOF
  chmod +x "${HOME}/.local/bin/laya-serve" "${HOME}/.local/bin/laya-mcp-server"
}

function _require_python3 {
  dybatpho::is command python3 || skip "python3 is not installed"
}

teardown() {
  pkill -f "http.server ${LAYA_SHARED_PORT}" || true
}

@test "laya-mcp starts one loopback laya-serve and points every session at it" {
  _require_python3
  run laya_mcp::main --flag
  assert_success
  assert_line "base=http://127.0.0.1:${LAYA_SHARED_PORT} preload= args=--flag"
  run laya_mcp::main
  assert_success
  run cat "${HOME}/serve.starts"
  assert_output start
  grep -qx 'LAYA_HOST=127.0.0.1' "${HOME}/serve.env"
  grep -qx 'LAYA_PRELOAD=0' "${HOME}/serve.env"
  grep -qx 'LAYA_IDLE_UNLOAD_SECONDS=900' "${HOME}/serve.env"
}

@test "laya-mcp keeps the caller's laya-serve tuning" {
  _require_python3
  LAYA_IDLE_UNLOAD_SECONDS=60 LAYA_PRELOAD=1 run laya_mcp::main
  assert_success
  grep -qx 'LAYA_IDLE_UNLOAD_SECONDS=60' "${HOME}/serve.env"
  grep -qx 'LAYA_PRELOAD=1' "${HOME}/serve.env"
}

@test "laya-mcp falls back to a lazy in-process router when laya-serve never listens" {
  printf '#!/usr/bin/env bash\nexit 1\n' > "${HOME}/.local/bin/laya-serve"
  LAYA_MCP_WAIT=1 run laya_mcp::main
  assert_success
  assert_line --partial "base= preload=0 args="
}
