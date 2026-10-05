#!/usr/bin/env bash
# @file autoclose.sh
# @brief Close an eww window as soon as the focus moves away from it
# @description The panel and the notification centre are layer surfaces, so the
# compositor never tells them they lost focus. This watches the Hyprland event
# stream instead and closes the window on the first event that means the user
# went somewhere else: another window taking focus, another monitor, another
# workspace.
#
# Opening a layer surface emits only `openlayer`, never `activewindow`, so a
# watcher started at the same moment as the window does not fire on its own.
set -euo pipefail
# dyshellint disable=BSG099 this drives Hyprland, so it never runs on macOS
shopt -s inherit_errexit

# Overridable so the config can be exercised from a throwaway eww daemon.
readonly CONFIG="${EWW_CONFIG_DIR:-${HOME}/.config/eww}"
readonly RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
readonly SCRIPTS="${CONFIG}/scripts"

# @description Print the file holding the watcher's process id for a window.
# @arg $1 string The eww window id.
# @stdout A file path.
function _pid_file {
  printf '%s/eww-autoclose-%s.pid\n' "${RUNTIME}" "$1"
}

# @description Stop the watcher of a window, if one is running.
# @description The whole process group goes, not just the shell: the watcher
# reads through `nc`, which would otherwise survive as an orphan still holding
# the compositor's event socket open.
# @arg $1 string The eww window id.
function _stop {
  local file pid

  file="$(_pid_file "$1")"
  [[ -r ${file} ]] || return 0
  pid="$(< "${file}")"
  rm -f "${file}"
  [[ -n ${pid} ]] || return 0
  kill -- -"${pid}" 2> /dev/null || kill "${pid}" 2> /dev/null || true
}

# @description Close the window on the first event that moves the focus away.
# @arg $1 string The eww window id.
function _watch {
  local window="$1" line

  # `setsid` gave this its own process group, so taking the group down on the
  # way out takes `nc` with it.
  trap 'kill 0 2> /dev/null' EXIT

  while read -r line; do
    case "${line}" in
      activewindow\>\>* | focusedmon\>\>* | workspace\>\>*)
        eww -c "${CONFIG}" close "${window}" 2> /dev/null || true
        rm -f "$(_pid_file "${window}")"
        return 0
        ;;
      *) ;;
    esac
  done < <(nc -U "$("${SCRIPTS}/hypr_socket.sh")")
}

# @description Dispatch on the requested action.
# @arg $1 string `watch`, `stop`, or `run` for the detached watcher itself.
# @arg $2 string The eww window id.
# @exitcode 1 When the action is unknown or the window id is missing.
function _main {
  local action="${1:-}" window="${2:-}"

  if [[ -z ${window} ]]; then
    printf '%s\n' "autoclose.sh: ${action:-the action} needs a window id" >&2
    return 1
  fi

  case "${action}" in
    watch)
      # Only ever one watcher per window, so a reopened panel is not closed by
      # the watcher of the one before it.
      _stop "${window}"
      # Its own session, so the whole thing can be taken down as a group.
      setsid "${BASH_SOURCE[0]}" run "${window}" < /dev/null &> /dev/null &
      printf '%s\n' "$!" > "$(_pid_file "${window}")"
      ;;
    run) _watch "${window}" ;;
    stop) _stop "${window}" ;;
    *)
      printf '%s\n' "autoclose.sh: unknown action '${action}'" >&2
      return 1
      ;;
  esac
}

_main "$@"
