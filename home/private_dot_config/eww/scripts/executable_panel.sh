#!/usr/bin/env bash
# @file panel.sh
# @brief Open, close or switch the eww detail panel
# @description Drive the detail panel next to the bar. `open` shows one section
# on one monitor, switching an already open panel rather than closing it, and
# `close` dismisses it wherever it is — the panel carries its own close button.
# Only one panel is ever open, so clicking a module on another monitor moves it
# there.
set -euo pipefail
# dyshellint disable=BSG099 this drives Hyprland, so it never runs on macOS
shopt -s inherit_errexit

readonly CONFIG="${HOME}/.config/eww"

# @description List the panel windows eww currently has open.
# @noargs
# @stdout One window id per line.
function _open_panels {
  eww -c "${CONFIG}" active-windows 2> /dev/null \
    | sed -n 's/^\(panel-[^:]*\):.*/\1/p'
}

# @description Close every panel window.
# @noargs
function _close {
  local window

  while read -r window; do
    [[ -n ${window} ]] || continue
    eww -c "${CONFIG}" close "${window}" || true
  done < <(_open_panels)
}

# @description Show one section on one monitor.
# @arg $1 string The section to show.
# @arg $2 string The monitor name to show it on.
function _open {
  local section="$1" monitor="$2" window showing

  showing="$(_open_panels | grep -cxF "panel-${monitor}" || true)"

  # Keep a single panel around: drop the ones on other monitors, but leave this
  # monitor's in place so switching sections does not blink the window.
  while read -r window; do
    [[ -n ${window} && ${window} != "panel-${monitor}" ]] || continue
    eww -c "${CONFIG}" close "${window}" || true
  done < <(_open_panels)

  eww -c "${CONFIG}" update "panel_section=${section}"

  if [[ ${showing} == 0 ]]; then
    eww -c "${CONFIG}" open panel \
      --id "panel-${monitor}" \
      --screen "${monitor}" \
      --arg "monitor=${monitor}"
  fi
}

# @description Dispatch on the requested action.
# @arg $1 string Either `open` or `close`.
# @arg $2 string The section, for `open`.
# @arg $3 string The monitor name, for `open`.
# @exitcode 1 When the action is unknown or `open` is missing an argument.
function _main {
  local action="${1:-close}"

  case "${action}" in
    open)
      if [[ -z ${2:-} || -z ${3:-} ]]; then
        printf '%s\n' "panel.sh: open needs a section and a monitor" >&2
        return 1
      fi
      _open "$2" "$3"
      ;;
    close) _close ;;
    *)
      printf '%s\n' "panel.sh: unknown action '${action}'" >&2
      return 1
      ;;
  esac
}

_main "$@"
