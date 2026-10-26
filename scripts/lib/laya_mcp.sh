# @file laya_mcp.sh
# @brief Launch the laya MCP server against one shared laya-serve
# @description Every agent session starts its own MCP servers, and a stock
# `laya-mcp-server` imports torch and preloads its checkpoints in-process:
# about 3.4 GB per session, enough to run a machine out of memory with a
# handful of sessions open. `laya-mcp` instead makes sure one `laya-serve`
# answers on the loopback interface, starting it in the background when no
# session has yet (`mcp_share::ensure_server`), then `exec`s `laya-mcp-server`
# in remote mode (`LAYA_BASE_URL`), which loads no model and imports no
# torch. The server unloads idle checkpoints.
# Sourced (not executed); the caller sources dybatpho with the `network` and
# `lock` modules and `mcp_share.sh` first and owns strict mode.
# shellcheck shell=bash

LAYA_MCP_DEFAULT_PORT=47821

#######################################
# @description Run laya-serve bound to the loopback interface, detached from the caller's stdio
# @arg $1 number Port to listen on
# @arg $2 string Log file
# @env LAYA_IDLE_UNLOAD_SECONDS number [default: 900] Unload checkpoints idle this long
# @env LAYA_PRELOAD string [default: 0] Load checkpoints lazily, on the first request
#######################################
function laya_mcp::serve {
  local port log
  dybatpho::expect_args port log -- "$@"
  # Never 0.0.0.0, laya-serve's default: the server takes no API key here.
  # stdin and stdout are the MCP pipe of the session that starts the server;
  # holding them would keep that pipe open after the session ends.
  LAYA_HOST=127.0.0.1 LAYA_PORT="${port}" \
    LAYA_PRELOAD="${LAYA_PRELOAD:-0}" \
    LAYA_IDLE_UNLOAD_SECONDS="${LAYA_IDLE_UNLOAD_SECONDS:-900}" \
    exec laya-serve < /dev/null &>> "${log}"
}

#######################################
# @description Succeed once laya-serve listens on the shared port
# @arg $1 number Seconds to wait
# @env LAYA_SHARED_PORT number [default: 47821] Port of the shared laya-serve
#######################################
function laya_mcp::probe {
  local wait
  dybatpho::expect_args wait -- "$@"
  dybatpho::wait_port 127.0.0.1 "${LAYA_SHARED_PORT:-${LAYA_MCP_DEFAULT_PORT}}" "${wait}" 1
}

#######################################
# @description Make sure a shared laya-serve listens on the port, starting one if none does
# @arg $1 number Port
# @arg $2 number Seconds to wait for a server this call starts
# @env LAYA_MCP_STATE_DIR string [default: ${XDG_STATE_HOME:-~/.local/state}/laya] Lock, pid and log directory
# @exitcode 0 A server listens on the port, or one is still starting
# @exitcode 1 None is running
#######################################
function laya_mcp::ensure_server {
  local port wait
  dybatpho::expect_args port wait -- "$@"
  # An install without the `serve` extra has no laya-serve to start.
  if ! dybatpho::is command laya-serve; then
    dybatpho::port_open 127.0.0.1 "${port}" 1
    return
  fi
  local state_dir="${LAYA_MCP_STATE_DIR-}"
  [[ -n "${state_dir}" ]] || state_dir="$(dybatpho::xdg_state_dir laya)"
  LAYA_SHARED_PORT="${port}" mcp_share::ensure_server "${state_dir}" "${wait}" \
    laya_mcp::probe laya_mcp::serve "${port}"
}

#######################################
# @description Start laya-mcp-server, answering from the shared laya-serve when it is up
# @arg $@ string Arguments passed through to laya-mcp-server
# @env LAYA_SHARED_PORT number [default: 47821] Port of the shared laya-serve
# @env LAYA_MCP_WAIT number [default: 10] Seconds to wait for the server to come up
# @stderr One line when it falls back to a local, lazily loaded router
#######################################
function laya_mcp::main {
  local port="${LAYA_SHARED_PORT:-${LAYA_MCP_DEFAULT_PORT}}"
  if laya_mcp::ensure_server "${port}" "${LAYA_MCP_WAIT:-10}"; then
    export LAYA_BASE_URL="http://127.0.0.1:${port}"
  else
    # Still usable, but loading lazily so a session that never calls laya
    # costs no model memory.
    dybatpho::warn "laya-serve did not come up on port ${port}, answering in-process"
    export LAYA_PRELOAD=0
  fi
  exec laya-mcp-server "$@"
}
