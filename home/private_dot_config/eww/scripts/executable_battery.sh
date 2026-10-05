#!/usr/bin/env bash
# @file battery.sh
# @brief Report the battery state for the eww bar and for hyprlock
# @description Report the charge, the charging state, an icon and the remaining
# time of the first real battery. `--json` feeds the eww widget, `--text` feeds
# the hyprlock label, and both report an absent battery on a machine with none.
set -euo pipefail
# dyshellint disable=BSG099 this drives Hyprland, so it never runs on macOS
shopt -s inherit_errexit

# A single line, because eww reads one JSON object per line.
readonly ABSENT='{"present":false,"capacity":0,"charging":false,"icon":"","level":"full","status":"","time":""}'

# @description Print the sysfs path of the first real battery, if there is one.
# @noargs
# @stdout The battery directory, or nothing.
function _find_battery {
  local battery

  for battery in /sys/class/power_supply/*; do
    [[ -r "${battery}/type" ]] || continue
    [[ $(< "${battery}/type") == "Battery" ]] || continue
    [[ -r "${battery}/capacity" ]] || continue
    printf '%s\n' "${battery}"
    return 0
  done
}

# @description Print the icon matching a charge level and a charging state.
# @arg $1 int The charge percentage.
# @arg $2 string `true` when the battery is charging.
# @stdout One nerd font glyph.
function _battery_icon {
  local capacity="$1" charging="$2"

  if [[ ${charging} == true ]]; then
    printf '%s\n' "󰂄"
  elif ((10#${capacity} >= 90)); then
    printf '%s\n' "󰁹"
  elif ((10#${capacity} >= 70)); then
    printf '%s\n' "󰂀"
  elif ((10#${capacity} >= 50)); then
    printf '%s\n' "󰁾"
  elif ((10#${capacity} >= 30)); then
    printf '%s\n' "󰁼"
  elif ((10#${capacity} >= 15)); then
    printf '%s\n' "󰁺"
  else
    printf '%s\n' "󰂎"
  fi
}

# @description Print how long the battery still lasts, as reported by upower.
# @noargs
# @stdout A human readable duration, or nothing.
function _remaining_time {
  command -v upower > /dev/null || return 0
  local device
  device="$(upower -e | grep -m1 BAT || true)"
  [[ -n ${device} ]] || return 0
  upower -i "${device}" 2> /dev/null \
    | sed -n 's/^ *time to \(empty\|full\): *\(.*\)$/\2/p' | head -1
}

# @description Print the battery state in the requested format.
# @arg $1 string Either `--json` (the default) or `--text`.
# @stdout One JSON object, or one line of text.
function _main {
  local format="${1:---json}"
  local battery capacity status charging icon time level

  battery="$(_find_battery)"
  if [[ -z ${battery} ]]; then
    case "${format}" in
      --text) printf '\n' ;;
      *) printf '%s\n' "${ABSENT}" ;;
    esac
    return 0
  fi

  capacity="$(< "${battery}/capacity")"
  status="$(< "${battery}/status")"
  if [[ ${status} == "Charging" || ${status} == "Full" ]]; then
    charging=true
  else
    charging=false
  fi
  icon="$(_battery_icon "${capacity}" "${charging}")"
  time="$(_remaining_time)"

  if [[ ${charging} == false ]] && ((10#${capacity} <= 15)); then
    level="critical"
  elif [[ ${charging} == false ]] && ((10#${capacity} <= 30)); then
    level="low"
  else
    level="full"
  fi

  case "${format}" in
    --text)
      if [[ ${charging} == true ]]; then
        printf '%s\n' "Đang sạc, hiện tại ${capacity}%"
      else
        printf '%s\n' "Còn lại ${capacity}%"
      fi
      ;;
    *)
      jq -nc \
        --argjson capacity "${capacity}" \
        --argjson charging "${charging}" \
        --arg icon "${icon}" \
        --arg level "${level}" \
        --arg status "${status}" \
        --arg time "${time}" \
        '{present: true, capacity: $capacity, charging: $charging, icon: $icon,
          level: $level, status: $status, time: $time}'
      ;;
  esac
}

_main "$@"
