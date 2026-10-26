# @file mcp_share.sh
# @brief Share one MCP backend process between every agent session
# @description Every agent session starts its own MCP servers. For a server
# that is heavy and keeps no per-session state, the stdio launcher an agent
# registers can instead make sure one shared backend runs on this machine,
# starting it in the background when no session has yet, and answer from it.
# The backend outlives the session that started it and needs no service
# manager, so the same launcher works under systemd, OpenRC and macOS.
# Sourced (not executed); the caller sources dybatpho with the `lock` module
# first and owns strict mode.
# shellcheck shell=bash

#######################################
# @description Make sure a shared backend answers, starting one if none does
# @arg $1 string State directory for the lock, pid and log files
# @arg $2 number Seconds to wait for a backend this call starts
# @arg $3 string Probe command, called with a number of seconds: succeeds once the backend answers within them
# @arg $@ string Command that runs the backend in the foreground, called with the log file appended
# @exitcode 0 The backend answers, or one is still starting
# @exitcode 1 None is running
#######################################
function mcp_share::ensure_server {
  local state_dir wait probe
  dybatpho::expect_args state_dir wait probe -- "$@"
  shift 3
  "${probe}" 0 && return 0
  local log lock pid_file
  # Owner only: the backend takes no credentials, so who may reach its
  # socket or read its log is settled by this directory alone.
  dybatpho::ensure_dir "${state_dir}" 700 > /dev/null
  log="$(dybatpho::path_join "${state_dir}" "serve.log")"
  lock="$(dybatpho::path_join "${state_dir}" "serve.lock")"
  pid_file="$(dybatpho::path_join "${state_dir}" "serve.pid")"
  # Sessions often start together: the lock lets one of them start the
  # backend while the others wait for it, instead of each starting its own.
  dybatpho::lock_acquire "${lock}" "${wait}" \
    || return 1
  # A backend still loading has not opened its socket yet: the pid file
  # keeps a later session from starting a second one beside it.
  if ! "${probe}" 0 && ! dybatpho::pid_file_is_running "${pid_file}"; then
    dybatpho::background_run mcp_share_server "$@" "${log}"
    local pid
    pid="$(dybatpho::background_pid mcp_share_server)"
    dybatpho::pid_file_write "${pid_file}" "${pid}"
  fi
  # A slow start still counts, as long as it ends before the agent gives up
  # on an MCP server (30s).
  local status=0
  "${probe}" "${wait}" || dybatpho::pid_file_is_running "${pid_file}" || status=1
  # Released before the caller execs: exec keeps this pid, so a lock still
  # held would look owned by a live process for the whole session.
  dybatpho::lock_release "${lock}"
  return "${status}"
}
