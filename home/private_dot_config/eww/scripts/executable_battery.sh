#!/usr/bin/env bash
# @file battery.sh
# @brief Report the battery state for the eww bar and for hyprlock
# @description Report the charge, the charging state, an icon and the remaining
# time of the first real battery. `--json` feeds the eww widget, `--text` feeds
# the hyprlock label, and both report an absent battery on a machine with none.
set -euo pipefail
# dyshellint disable=BSG099 this drives Hyprland, so it never runs on macOS
shopt -s inherit_errexit

# Printed in two pieces to keep the source lines short; it stays one line of
# output, which is what eww reads.
readonly ABSENT_HEAD='{"present":false,"capacity":0,"charging":false,"icon":"","level":"full",'
readonly ABSENT_TAIL='"status":"","time":"","health":0,"cycles":0,"power":0,"model":""}'

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

# @description Read one sysfs attribute of a battery, or print a fallback.
# @arg $1 string The battery directory.
# @arg $2 string The attribute file name.
# @arg $3 string The value to print when the attribute is missing.
# @stdout The attribute value.
function _attribute {
  if [[ -r "$1/$2" ]]; then
    cat -- "$1/$2"
  else
    printf '%s\n' "$3"
  fi
}

# @description Print the battery state in the requested format.
# @arg $1 string Either `--json` (the default) or `--text`.
# @stdout One JSON object, or one line of text.
function _main {
  local format="${1:---json}"
  local battery capacity status charging icon time level
  local full design health cycles power model

  battery="$(_find_battery)"
  if [[ -z ${battery} ]]; then
    case "${format}" in
      --text) printf '\n' ;;
      *) printf '%s%s\n' "${ABSENT_HEAD}" "${ABSENT_TAIL}" ;;
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
  # Health is what the pack still holds against what it shipped with; sysfs
  # reports both in microwatt hours, and a missing pair reads as 0.
  full="$(_attribute "${battery}" energy_full 0)"
  design="$(_attribute "${battery}" energy_full_design 0)"
  health=0
  ((design > 0)) && health=$((full * 100 / design))
  cycles="$(_attribute "${battery}" cycle_count 0)"
  # sysfs reports the draw in microwatts; one decimal of a watt is plenty.
  power="$(_attribute "${battery}" power_now 0 | awk '{ printf "%.1f", $1 / 1000000 }')"
  model="$(_attribute "${battery}" model_name "")"

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
      CAPACITY="${capacity}" CHARGING="${charging}" ICON="${icon}" \
        LEVEL="${level}" STATUS="${status}" TIME="${time}" \
        HEALTH="${health}" CYCLES="${cycles}" POWER="${power}" MODEL="${model}" \
        yq -n -o json -I 0 '{
          "present": true,
          "capacity": env(CAPACITY),
          "charging": env(CHARGING),
          "icon": strenv(ICON),
          "level": strenv(LEVEL),
          "status": strenv(STATUS),
          "time": strenv(TIME),
          "health": env(HEALTH),
          "cycles": env(CYCLES),
          "power": env(POWER),
          "model": strenv(MODEL)
        }'
      ;;
  esac
}

_main "$@"
