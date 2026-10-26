#!/usr/bin/env bash
# @file volume.sh
# @brief Show the output volume
# @description Run by the `volume` item on volume_change, which passes the new
# volume in INFO; asks osascript for it when run any other way.
set -euo pipefail

name=${NAME:-volume}
volume=${INFO:-}
if [[ "${SENDER:-}" != "volume_change" || -z "${volume}" ]]; then
  volume=$(osascript -e 'output volume of (get volume settings)')
fi

if ((volume > 60)); then
  icon="󰕾"
elif ((volume > 30)); then
  icon="󰖀"
elif ((volume > 0)); then
  icon="󰕿"
else
  icon="󰖁"
fi
sketchybar --set "${name}" icon="${icon}" label="${volume}%"
