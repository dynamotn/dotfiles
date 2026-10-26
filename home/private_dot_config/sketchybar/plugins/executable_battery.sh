#!/usr/bin/env bash
# @file battery.sh
# @brief Show the battery charge and whether it is charging
# @description Run by the `battery` item. Hides the item on a Mac without a
# battery, where pmset reports no percentage.
set -euo pipefail

name=${NAME:-battery}
info=$(pmset -g batt)
percentage=$(grep -Eo '[0-9]+%' <<< "${info}" | tr -d '%' || true)
if [[ -z "${percentage}" ]]; then
  sketchybar --set "${name}" drawing=off
  exit 0
fi

if [[ "${info}" == *"AC Power"* ]]; then
  icon="󰂄"
elif ((percentage > 80)); then
  icon=""
elif ((percentage > 60)); then
  icon=""
elif ((percentage > 35)); then
  icon=""
elif ((percentage > 10)); then
  icon=""
else
  icon=""
fi
sketchybar --set "${name}" drawing=on icon="${icon}" label="${percentage}%"
