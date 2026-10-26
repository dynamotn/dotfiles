# @file dybrain_mcp.sh
# @brief Launch the dybrain MCP server against one shared backend
# @description The vault's own MCP server (`vault-mcp.py`, run by
# `uv run --script`) costs about 120 MB per agent session, Python and the MCP
# SDK included, and keeps no state between calls: it re-reads the vault on
# every call and resolves every path against the vault, never the caller's
# working directory. `dybrain-mcp` instead makes sure one backend serves it
# over streamable HTTP (stateless, JSON replies) on a Unix socket in an
# owner-only state directory, starting it when no session has yet
# (`mcp_share::ensure_server`), then bridges the session's stdio to it with
# curl, one POST per message. The backend imports the vault's script
# unchanged and only swaps its transport, so the tools stay defined in the
# vault. Sourced (not executed); the caller sources dybatpho with the `lock`
# module and `mcp_share.sh` first and owns strict mode.
# shellcheck shell=bash

# Runs in the script's own uv environment: loads vault-mcp.py as a module and
# runs its main() with MCPServer.run answering on the socket instead of stdio.
DYBRAIN_MCP_HTTP_PY='
import importlib.util, logging, sys
import uvicorn
from mcp.server.mcpserver import MCPServer
script, sock = sys.argv[1:3]
def run(self, transport="stdio", **_):
    app = self.streamable_http_app(json_response=True, stateless_http=True)
    uvicorn.run(app, uds=sock, log_level="warning")
MCPServer.run = run
logging.getLogger("mcp").setLevel(logging.WARNING)  # a line per stateless request otherwise
spec = importlib.util.spec_from_file_location("dybrain_vault_mcp", script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.main()
'

# The host must carry a port: the SDK's DNS-rebinding guard only accepts
# `localhost:*`. curl talks to the socket, so the port is never dialled.
DYBRAIN_MCP_URL="http://localhost:1/mcp"

#######################################
# @description Print the directory of the backend's socket, lock, pid and log
# @noargs
# @env DYBRAIN_MCP_STATE_DIR string [default: ${XDG_STATE_HOME:-~/.local/state}/dybrain] That directory
# @stdout The directory
#######################################
function dybrain_mcp::state_dir {
  local dir="${DYBRAIN_MCP_STATE_DIR-}"
  [[ -n "${dir}" ]] || dir="$(dybatpho::xdg_state_dir dybrain)"
  printf '%s\n' "${dir}"
}

#######################################
# @description POST one JSON-RPC message to the backend
# @arg $1 string The message
# @arg $2 number Seconds the whole request may take
# @stdout The reply body; empty for a notification
# @exitcode 0 The backend answered with a 2xx status
#######################################
function dybrain_mcp::post {
  local message max_time
  dybatpho::expect_args message max_time -- "$@"
  local state_dir
  state_dir="$(dybrain_mcp::state_dir)"
  curl -sSf --max-time "${max_time}" --unix-socket "${state_dir}/serve.sock" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    --data-binary @- "${DYBRAIN_MCP_URL}" <<< "${message}"
}

#######################################
# @description Succeed once the backend answers a ping
# @arg $1 number Seconds to wait
#######################################
function dybrain_mcp::probe {
  local wait
  dybatpho::expect_args wait -- "$@"
  local deadline=$((SECONDS + 10#${wait}))
  until dybrain_mcp::post '{"jsonrpc":"2.0","id":0,"method":"ping"}' 1 &> /dev/null; do
    ((SECONDS < deadline)) || return 1
    sleep 0.2
  done
}

#######################################
# @description Run the backend on the socket, detached from the caller's stdio
# @arg $1 string Path of vault-mcp.py
# @arg $2 string Log file
#######################################
function dybrain_mcp::serve {
  local script log
  dybatpho::expect_args script log -- "$@"
  local state_dir python
  state_dir="$(dybrain_mcp::state_dir)"
  # Only reached when nothing answers and no backend is alive, under the
  # lock: a socket left here is stale, and binding over it would fail.
  rm -f -- "${state_dir}/serve.sock"
  # stdin and stdout are the MCP pipe of the session that starts the backend;
  # holding them would keep that pipe open after the session ends.
  exec < /dev/null &>> "${log}"
  uv sync --quiet --script "${script}"
  python="$(uv python find --script "${script}")"
  exec "${python}" -I -c "${DYBRAIN_MCP_HTTP_PY}" "${script}" "${state_dir}/serve.sock"
}

#######################################
# @description Send one message to the backend, restarting it once if it went away
# @arg $1 string The message
# @arg $2 string Path of vault-mcp.py
# @arg $3 number Seconds to wait for a restarted backend
# @stdout The reply body; empty for a notification
#######################################
function dybrain_mcp::relay {
  local message script wait
  dybatpho::expect_args message script wait -- "$@"
  # Tool calls may run long (a vault-wide search); the agent has its own timeout.
  dybrain_mcp::post "${message}" 600 && return 0
  # The shared backend may have been killed or crashed since the session began.
  local state_dir
  state_dir="$(dybrain_mcp::state_dir)"
  mcp_share::ensure_server "${state_dir}" "${wait}" dybrain_mcp::probe \
    dybrain_mcp::serve "${script}" || return 1
  dybrain_mcp::post "${message}" 600
}

#######################################
# @description Relay MCP messages between stdio and the backend until stdin closes
# @arg $1 string Path of vault-mcp.py, to restart a backend that went away
# @arg $2 number Seconds to wait for a restarted backend
# @stdout One reply line per request
#######################################
function dybrain_mcp::bridge {
  local script wait
  dybatpho::expect_args script wait -- "$@"
  local line reply id
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -n "${line//[[:space:]]/}" ]] || continue
    # shellcheck disable=SC2310 # a failed relay is answered below
    reply="$(dybrain_mcp::relay "${line}" "${script}" "${wait}")" || {
      id="$(jq -c 'select(type == "object" and has("id")) | .id' <<< "${line}" 2> /dev/null)" || id=""
      [[ -n "${id}" ]] || continue
      reply="$(jq -cn --argjson id "${id}" \
        '{jsonrpc: "2.0", id: $id, error: {code: -32603, message: "dybrain backend is not answering"}}')"
    }
    [[ -z "${reply}" ]] || printf '%s\n' "${reply}"
  done
}

#######################################
# @description Serve dybrain on stdio, from the shared backend when it comes up
# @arg $1 string Path of vault-mcp.py
# @env DYBRAIN_MCP_WAIT number [default: 10] Seconds to wait for the backend to come up
# @stderr One line when it falls back to a server of its own
#######################################
function dybrain_mcp::main {
  local script
  dybatpho::expect_args script -- "$@"
  local wait="${DYBRAIN_MCP_WAIT:-10}" state_dir
  state_dir="$(dybrain_mcp::state_dir)"
  # shellcheck disable=SC2310 # the fallback below handles a failed start
  if dybatpho::is command curl && dybatpho::is command jq \
    && mcp_share::ensure_server "${state_dir}" "${wait}" dybrain_mcp::probe \
      dybrain_mcp::serve "${script}"; then
    dybrain_mcp::bridge "${script}" "${wait}"
    return
  fi
  dybatpho::warn "dybrain backend did not come up in ${state_dir}, answering in-process"
  exec uv run --script "${script}"
}
