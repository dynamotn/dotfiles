setup() {
  load test_helper
  setup_dotfiles_test_env
  # shellcheck disable=SC2154 # DOTFILES_DIR is set by test_helper.bash
  . "${DOTFILES_DIR}/scripts/lib/mcp_share.sh"
  . "${DOTFILES_DIR}/scripts/lib/dybrain_mcp.sh"
  # The real interpreter, past any wrapper an agent session puts first on PATH.
  PYTHON3="$(type -P -a python3 | grep -v /shims/ | head -n 1)" || true
  [[ -n "${PYTHON3}" ]] || skip "python3 is not installed"
  export PYTHON3
  dybatpho::is command curl || skip "curl is not installed"
  export DYBRAIN_MCP_WAIT=10
  SCRIPT="${HOME}/vault-mcp.py"
  touch "${SCRIPT}"
  # Stand-in backend: answers each request with its method and pid over
  # HTTP on the socket, and a notification with 202 and no body.
  cat > "${HOME}/backend.py" << 'EOF2'
import http.server, json, os, socketserver, sys
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        msg = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if "id" not in msg:
            self.send_response(202)
            self.end_headers()
            return
        body = json.dumps({"jsonrpc": "2.0", "id": msg["id"],
                           "result": {"method": msg["method"], "pid": os.getpid()}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    def get_request(self):
        return super().get_request()[0], ("local", 0)
Server(sys.argv[1], Handler).serve_forever()
EOF2
  # uv stub: `python find` names the stand-in, `run` is the in-process fallback.
  cat > "${HOME}/.local/bin/uv" << 'EOF2'
#!/usr/bin/env bash
case "$1 $2" in
  "python find") echo "${HOME}/python" ;;
  "run --script") echo "in-process $3" ;;
esac
EOF2
  cat > "${HOME}/python" << 'EOF2'
#!/usr/bin/env bash
echo "$*" | grep -q -- '-I -c' || exit 2
echo start >> "${HOME}/serve.starts"
exec "${PYTHON3}" "${HOME}/backend.py" "${@: -1}"
EOF2
  chmod +x "${HOME}/.local/bin/uv" "${HOME}/python"
  PING='{"jsonrpc":"2.0","id":7,"method":"tools/list"}'
  NOTE='{"jsonrpc":"2.0","method":"notifications/initialized"}'
}

teardown() {
  local pid_file="${HOME}/.local/state/dybrain/serve.pid"
  [[ -f "${pid_file}" ]] && kill "$(< "${pid_file}")" 2> /dev/null || true
}

@test "dybrain-mcp bridges every session to one backend" {
  run --separate-stderr dybrain_mcp::main "${SCRIPT}" <<< "${NOTE}"$'\n'"${PING}"
  assert_success
  assert_output --regexp '^\{"jsonrpc": "2.0", "id": 7, "result": \{"method": "tools/list", "pid": [0-9]+\}\}$'
  local first="${output}"
  run --separate-stderr dybrain_mcp::main "${SCRIPT}" <<< "${PING}"
  assert_success
  assert_output "${first}"
  run cat "${HOME}/serve.starts"
  assert_output start
  [[ -S "${HOME}/.local/state/dybrain/serve.sock" ]]
}

@test "dybrain-mcp replaces a stale socket and a backend that went away" {
  mkdir -p "${HOME}/.local/state/dybrain"
  touch "${HOME}/.local/state/dybrain/serve.sock"
  run dybrain_mcp::main "${SCRIPT}" <<< "${PING}"
  assert_success
  kill "$(< "${HOME}/.local/state/dybrain/serve.pid")"
  sleep 0.5
  run dybrain_mcp::bridge "${SCRIPT}" 10 <<< "${PING}"
  assert_success
  assert_output --partial '"id": 7, "result"'
  run cat "${HOME}/serve.starts"
  assert_output $'start\nstart'
}

@test "dybrain-mcp answers in-process when the backend never comes up" {
  printf '#!/usr/bin/env bash\nexit 1\n' > "${HOME}/python"
  DYBRAIN_MCP_WAIT=1 run dybrain_mcp::main "${SCRIPT}"
  assert_success
  assert_line "in-process ${SCRIPT}"
}

@test "dybrain-mcp answers a request with an error when the backend is gone" {
  printf '#!/usr/bin/env bash\nexit 1\n' > "${HOME}/python"
  run dybrain_mcp::bridge "${SCRIPT}" 1 <<< "${NOTE}"$'\n'"${PING}"
  assert_success
  assert_line '{"jsonrpc":"2.0","id":7,"error":{"code":-32603,"message":"dybrain backend is not answering"}}'
}
