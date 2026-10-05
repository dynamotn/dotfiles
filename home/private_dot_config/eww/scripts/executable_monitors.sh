#!/usr/bin/env bash
# @file monitors.sh
# @brief Keep one bar window open on every connected monitor
# @description Open the eww bar on every monitor Hyprland currently reports,
# then follow the Hyprland event socket and open or close bar windows as
# monitors are plugged, unplugged, or created by shikane and wayvnc. Each window
# gets its own id and is passed the monitor name, so the bar keeps following the
# right output across a reconfiguration.
set -euo pipefail

# Overridable so the config can be exercised from a throwaway eww daemon.
readonly CONFIG="${EWW_CONFIG_DIR:-${HOME}/.config/eww}"
readonly SCRIPTS="${CONFIG}/scripts"

# @description List the names of every monitor Hyprland currently drives.
# @noargs
# @stdout One monitor name per line.
function _monitor_names {
  # `-o yaml` prints the names unquoted, one per line, and keeps yq from
  # warning about an unspecified output format.
  hyprctl monitors -j \
    | yq -p json -o yaml '.[] | select(.disabled == false) | .name'
}

# @description List the monitors eww currently has a bar window for.
# @noargs
# @stdout One monitor name per line.
function _open_bars {
  eww -c "${CONFIG}" active-windows 2> /dev/null \
    | sed -n 's/^bar-\([^:]*\):.*/\1/p'
}

# @description Open and close bar windows so they match the connected monitors.
# @noargs
function _sync_bars {
  local -a wanted open
  local name

  mapfile -t wanted < <(_monitor_names)
  mapfile -t open < <(_open_bars)

  for name in "${wanted[@]}"; do
    [[ -n ${name} ]] || continue
    if ! printf '%s\n' "${open[@]}" | grep -qxF "${name}"; then
      eww -c "${CONFIG}" open bar \
        --id "bar-${name}" \
        --screen "${name}" \
        --arg "monitor=${name}" || true
    fi
  done

  for name in "${open[@]}"; do
    [[ -n ${name} ]] || continue
    if ! printf '%s\n' "${wanted[@]}" | grep -qxF "${name}"; then
      eww -c "${CONFIG}" close "bar-${name}" || true
    fi
  done
}

# @description Open the bars, then resync them on every monitor change.
# @noargs
function _main {
  local event

  eww -c "${CONFIG}" daemon || true
  _sync_bars

  # Hyprland renames and renumbers outputs a moment after the event fires, so
  # settle briefly before asking it for the new list.
  while read -r event; do
    case "${event}" in
      monitoradded* | monitorremoved* | configreloaded*)
        sleep 0.5
        _sync_bars
        ;;
      *) ;;
    esac
  done < <(nc -U "$("${SCRIPTS}/hypr_socket.sh")")
}

_main "$@"
