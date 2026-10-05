#!/usr/bin/env bash
# @file idle.sh
# @brief Show or hide the eww idle screen on every monitor
# @description Open the eww idle screen on every connected monitor, or close the
# ones that are open. hypridle calls this before it hands over to hyprlock, so
# the idle screen is only ever a cover, never the lock itself.
set -euo pipefail

readonly CONFIG="${HOME}/.config/eww"

# @description List the names of every monitor Hyprland currently drives.
# @noargs
# @stdout One monitor name per line.
function _monitor_names {
  # `-o yaml` prints the names unquoted, one per line, and keeps yq from
  # warning about an unspecified output format.
  hyprctl monitors -j \
    | yq -p json -o yaml '.[] | select(.disabled == false) | .name'
}

# @description Open the idle screen on every connected monitor.
# @noargs
function _open {
  local name

  while read -r name; do
    eww -c "${CONFIG}" open idle \
      --id "idle-${name}" \
      --screen "${name}" \
      --arg "monitor=${name}" || true
  done < <(_monitor_names)
}

# @description Close every idle screen eww currently has open.
# @noargs
function _close {
  local window

  while read -r window; do
    [[ -n ${window} ]] || continue
    eww -c "${CONFIG}" close "${window}" || true
  done < <(
    eww -c "${CONFIG}" active-windows 2> /dev/null \
      | sed -n 's/^\(idle-[^:]*\):.*/\1/p'
  )
}

# @description Dispatch on the requested action.
# @arg $1 string Either `open` or `close`; `open` by default.
# @exitcode 1 When the action is neither.
function _main {
  local action="${1:-open}"

  case "${action}" in
    open) _open ;;
    close) _close ;;
    *)
      printf '%s\n' "idle.sh: unknown action '${action}', expected 'open' or 'close'" >&2
      return 1
      ;;
  esac
}

_main "$@"
