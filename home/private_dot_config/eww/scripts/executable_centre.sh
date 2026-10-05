#!/usr/bin/env bash
# @file centre.sh
# @brief Open, close or toggle the eww notification centre
# @description Which window is on screen is eww's business rather than
# dynotify's, so this stays here while everything that acts on a notification
# goes through the `dynotify` command.
set -euo pipefail
# dyshellint disable=BSG099 this drives Hyprland, so it never runs on macOS
shopt -s inherit_errexit

# Overridable so the config can be exercised from a throwaway eww daemon.
readonly CONFIG="${EWW_CONFIG_DIR:-${HOME}/.config/eww}"

# @description List the notification centre windows eww has open.
# @noargs
# @stdout One window id per line.
function _open_centres {
  eww -c "${CONFIG}" active-windows 2> /dev/null \
    | sed -n 's/^\(notification_centre-[^:]*\):.*/\1/p'
}

# @description Close every notification centre window.
# @noargs
function _close {
  local window

  while read -r window; do
    [[ -n ${window} ]] || continue
    eww -c "${CONFIG}" close "${window}" || true
  done < <(_open_centres)
}

# @description Open the centre on the monitor Hyprland currently focuses.
# @noargs
function _open {
  local monitor

  monitor="$(hyprctl monitors -j | yq -p json -o yaml '.[] | select(.focused == true) | .name')"
  [[ -n ${monitor} ]] || return 0
  _close
  eww -c "${CONFIG}" open notification_centre \
    --id "notification_centre-${monitor}" \
    --screen "${monitor}" \
    --arg "monitor=${monitor}"
}

# @description Dispatch on the requested action.
# @arg $1 string `toggle`, `open` or `close`; `toggle` by default.
# @exitcode 1 When the action is unknown.
function _main {
  case "${1:-toggle}" in
    open) _open ;;
    close) _close ;;
    toggle)
      if [[ -n "$(_open_centres)" ]]; then
        _close
      else
        _open
      fi
      ;;
    *)
      printf '%s\n' "centre.sh: unknown action '${1:-}'" >&2
      return 1
      ;;
  esac
}

_main "$@"
