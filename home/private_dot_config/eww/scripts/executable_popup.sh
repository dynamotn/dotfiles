#!/usr/bin/env bash
# @file popup.sh
# @brief Open, close or toggle an eww window on the focused monitor
# @description Every window that behaves like a popup — the notification
# centre, the calendar — wants the same thing: one instance, on whichever
# monitor has focus, closing itself when the focus moves away. This is that
# behaviour, once, for any of them.
set -euo pipefail
# dyshellint disable=BSG099 this drives Hyprland, so it never runs on macOS
shopt -s inherit_errexit

# Overridable so the config can be exercised from a throwaway eww daemon.
readonly CONFIG="${EWW_CONFIG_DIR:-${HOME}/.config/eww}"
readonly SCRIPTS="${CONFIG}/scripts"

# @description List the open instances of a window, whatever monitor they are on.
# @arg $1 string The window name.
# @stdout One window id per line.
function _open_ids {
  eww -c "${CONFIG}" active-windows 2> /dev/null \
    | sed -n "s/^\($1-[^:]*\):.*/\1/p"
}

# @description Close every instance of a window.
# @arg $1 string The window name.
function _close {
  local window

  while read -r window; do
    [[ -n ${window} ]] || continue
    eww -c "${CONFIG}" close "${window}" || true
    "${SCRIPTS}/autoclose.sh" stop "${window}" || true
  done < <(_open_ids "$1")
}

# @description Open a window on the monitor Hyprland currently focuses.
# @arg $1 string The window name.
function _open {
  local window="$1" monitor

  monitor="$(hyprctl monitors -j | yq -p json -o yaml '.[] | select(.focused == true) | .name')"
  [[ -n ${monitor} ]] || return 0
  _close "${window}"
  eww -c "${CONFIG}" open "${window}" \
    --id "${window}-${monitor}" \
    --screen "${monitor}" \
    --arg "monitor=${monitor}"
  # Clicking anywhere else should put it away, which the compositor has to tell
  # us about: a layer surface never hears that it lost focus.
  "${SCRIPTS}/autoclose.sh" watch "${window}-${monitor}" || true
}

# @description Dispatch on the requested action.
# @arg $1 string `toggle`, `open` or `close`.
# @arg $2 string The window name.
# @exitcode 1 When the action is unknown or the window is missing.
function _main {
  local action="${1:-toggle}" window="${2:-}"

  if [[ -z ${window} ]]; then
    printf '%s\n' "popup.sh: ${action} needs a window name" >&2
    return 1
  fi

  case "${action}" in
    open) _open "${window}" ;;
    close) _close "${window}" ;;
    toggle)
      if [[ -n "$(_open_ids "${window}")" ]]; then
        _close "${window}"
      else
        _open "${window}"
      fi
      ;;
    *)
      printf '%s\n' "popup.sh: unknown action '${action}'" >&2
      return 1
      ;;
  esac
}

_main "$@"
