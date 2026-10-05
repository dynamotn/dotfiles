#!/usr/bin/env bash
# @file network.sh
# @brief Stream the primary network connection state for the eww bar
# @description Print the kind, name, signal strength and an icon of the
# connection NetworkManager is currently routing through as one JSON line,
# then reprint it on every NetworkManager event rather than polling.
set -euo pipefail
# dyshellint disable=BSG099 this drives Hyprland, so it never runs on macOS
shopt -s inherit_errexit

# @description Print the icon matching a Wi-Fi signal strength.
# @arg $1 int The signal strength, as a percentage.
# @stdout One nerd font glyph.
function _wifi_icon {
  local signal="$1"

  if ((10#${signal} >= 75)); then
    printf '%s\n' "󰤨"
  elif ((10#${signal} >= 50)); then
    printf '%s\n' "󰤥"
  elif ((10#${signal} >= 25)); then
    printf '%s\n' "󰤢"
  else
    printf '%s\n' "󰤟"
  fi
}

# @description Print the current connection state as a JSON object.
# @noargs
# @stdout One JSON object.
function _emit {
  local state line type device name signal icon

  state="$(nmcli -t -f STATE general 2> /dev/null || printf '%s\n' "unknown")"

  # The first connected row of `nmcli device` is the one carrying the default
  # route, since nmcli orders devices by activation priority.
  line="$(
    nmcli -t -f TYPE,DEVICE,STATE,CONNECTION device 2> /dev/null \
      | awk -F: '$3 == "connected" { print; exit }'
  )"
  IFS=: read -r type device _ name <<< "${line}"
  signal=0

  case "${type}" in
    wifi)
      signal="$(
        nmcli -t -f IN-USE,SIGNAL device wifi list ifname "${device}" 2> /dev/null \
          | awk -F: '$1 == "*" { print $2; exit }'
      )"
      signal="${signal:-0}"
      icon="$(_wifi_icon "${signal}")"
      ;;
    ethernet) icon="󰈀" ;;
    wireguard | tun | vpn) icon="󰖂" ;;
    "")
      icon="󰤭"
      name="Disconnected"
      ;;
    *) icon="󰛳" ;;
  esac

  jq -nc \
    --arg type "${type:-none}" \
    --arg name "${name:-Disconnected}" \
    --arg icon "${icon}" \
    --arg state "${state}" \
    --argjson signal "${signal}" \
    '{type: $type, name: $name, icon: $icon, state: $state, signal: $signal}'
}

# @description Print the connection state once, then on every NetworkManager event.
# @noargs
# @stdout One JSON object per line.
function _main {
  _emit
  # `nmcli monitor` prints a line per change and never exits while
  # NetworkManager is up; debounce it so a reconnection storm does not fan out
  # into one emit per line.
  while read -r _; do
    sleep 0.3
    _emit
  done < <(nmcli monitor 2> /dev/null)
}

_main "$@"
