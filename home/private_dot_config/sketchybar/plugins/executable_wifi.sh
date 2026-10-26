#!/usr/bin/env bash
# @file wifi.sh
# @brief Show whether Wi-Fi has an address
# @description Run by the `wifi` item. macOS hides the SSID from scripts
# without location access, so only the connection state is shown.
set -euo pipefail

name=${NAME:-wifi}
if ipconfig getifaddr en0 &> /dev/null; then
  sketchybar --set "${name}" icon="󰖩"
else
  sketchybar --set "${name}" icon="󰖪"
fi
