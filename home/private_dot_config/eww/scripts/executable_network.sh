#!/usr/bin/env bash
# @file network.sh
# @brief Stream the network state for the eww bar and its panel
# @description Print the connection NetworkManager is routing through, its
# address, the Wi-Fi radio state and every saved connection as one JSON line,
# then reprint it on every NetworkManager event rather than polling.
set -euo pipefail
# dyshellint disable=BSG099 this drives Hyprland, so it never runs on macOS
shopt -s inherit_errexit

# The query that folds the collected values into the shape the widgets read.
# `-t` escapes a colon inside a field, and NAME is the only field that can hold
# one, so it goes last and the query splits off the three fixed fields first.
# The UUID is what the panel acts on: a name with a quote in it would break the
# shell command eww builds for a click.
# dyshellint disable=SC2016 the $ names are yq variables, not shell expansions
readonly PROGRAM='{
  "type": strenv(TYPE),
  "name": strenv(NAME),
  "icon": strenv(ICON),
  "state": strenv(STATE),
  "signal": env(SIGNAL),
  "device": strenv(DEVICE),
  "address": strenv(ADDRESS),
  "wifi_enabled": (strenv(WIFI) == "enabled"),
  "connections": (
    strenv(CONNECTIONS)
    | split("\n")
    | map(select(. != ""))
    | map(capture("^(?P<type>[^:]*):(?P<device>[^:]*):(?P<uuid>[^:]*):(?P<name>.*)$"))
    | map(select(.type | test("wireless|ethernet|wireguard|vpn")))
    | map({
        "name": (.name | sub("\\\\:"; ":")),
        "uuid": .uuid,
        "type": .type,
        "active": (.device != "")
      })
  )
}'

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

# @description Print the current network state as a JSON object.
# @noargs
# @stdout One JSON object.
function _emit {
  local state line type device name signal icon address wifi connections

  state="$(nmcli -t -f STATE general 2> /dev/null || printf '%s\n' "unknown")"
  wifi="$(nmcli radio wifi 2> /dev/null || printf '%s\n' "disabled")"

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

  address=""
  if [[ -n ${device} ]]; then
    address="$(
      nmcli -t -f IP4.ADDRESS device show "${device}" 2> /dev/null \
        | head -1 | cut -d: -f2
    )"
  fi
  connections="$(nmcli -t -f TYPE,DEVICE,UUID,NAME connection show 2> /dev/null || true)"

  TYPE="${type:-none}" NAME="${name:-Disconnected}" ICON="${icon}" \
    STATE="${state}" SIGNAL="${signal}" DEVICE="${device:-}" \
    ADDRESS="${address:-No address}" WIFI="${wifi}" \
    CONNECTIONS="${connections}" \
    yq -n -o json -I 0 "${PROGRAM}"
}

# @description Print the state once, then on every NetworkManager event.
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
