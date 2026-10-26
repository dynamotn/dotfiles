# @file laya_mcp.sh
# @brief Launch the laya MCP server against one shared laya-serve
# @description Every agent session starts its own MCP servers, and a stock
# `laya-mcp-server` imports torch and preloads its checkpoints in-process:
# about 3.4 GB per session, enough to run a machine out of memory with a
# handful of sessions open. `laya-mcp` instead makes sure one `laya-serve`
# answers on the loopback interface, starting it in the background when no
# session has yet, then `exec`s `laya-mcp-server` in remote mode
# (`LAYA_BASE_URL`), which loads no model and imports no torch. The server
# outlives the session that started it, unloads idle checkpoints, and needs no
# service manager, so the same launcher works under systemd, OpenRC and macOS.
# Sourced (not executed); the caller sources dybatpho with the `network` and
# `lock` modules first and owns strict mode.
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
# @description Make sure a shared laya-serve listens on the port, starting one if none does
# @arg $1 number Port
# @arg $2 number Seconds to wait for a server this call starts
# @env LAYA_MCP_STATE_DIR string [default: ${XDG_STATE_HOME:-~/.local/state}/laya] Lock, pid and log directory
# @exitcode 0 A server listens on the port, or one is still starting
# @exitcode 1 None is running
#######################################
function laya_mcp::ensure_server {
  local port wait state_dir log lock pid_file
  dybatpho::expect_args port wait -- "$@"
  dybatpho::port_open 127.0.0.1 "${port}" 1 && return 0
  # An install without the `serve` extra has no laya-serve to start.
  dybatpho::is command laya-serve || return 1
  state_dir="${LAYA_MCP_STATE_DIR:-$(dybatpho::xdg_state_dir laya)}"
  dybatpho::ensure_dir "${state_dir}" > /dev/null
  log="$(dybatpho::path_join "${state_dir}" "serve.log")"
  lock="$(dybatpho::path_join "${state_dir}" "serve.lock")"
  pid_file="$(dybatpho::path_join "${state_dir}" "serve.pid")"
  # Sessions often start together: the lock lets one of them start the
  # server while the others wait for it, instead of each starting its own.
  dybatpho::lock_acquire "${lock}" "${wait}" \
    || return 1
  # A server still importing torch has not opened its port yet: the pid
  # file keeps a later session from starting a second one beside it.
  if ! dybatpho::port_open 127.0.0.1 "${port}" 1 \
    && ! dybatpho::pid_file_is_running "${pid_file}"; then
    dybatpho::background_run laya_serve laya_mcp::serve "${port}" "${log}"
    local pid
    pid="$(dybatpho::background_pid laya_serve)"
    dybatpho::pid_file_write "${pid_file}" "${pid}"
  fi
  # A slow start still counts: remote mode connects on the first tool call,
  # not at startup, and the agent gives up on an MCP server after 30s.
  local status=0
  dybatpho::wait_port 127.0.0.1 "${port}" "${wait}" 1 \
    || dybatpho::pid_file_is_running "${pid_file}" || status=1
  # Released before the caller execs: exec keeps this pid, so a lock still
  # held would look owned by a live process for the whole session.
  dybatpho::lock_release "${lock}"
  return "${status}"
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
