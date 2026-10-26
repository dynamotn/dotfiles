#!/usr/bin/env bash
# @file status.sh
# @brief Declare the status widgets at the end of the bar
# @description Declare, from the right edge inwards, the session button, the
# battery, the volume and the Wi-Fi, in the order the noctalia bar ends with.
# Right items stack from the edge, so the first one added is the rightmost.
# Run by sketchybarrc before indicators.sh, which goes left of them.
set -euo pipefail

#######################################
# @description Declare every status item
# @noargs
#######################################
function _main {
  local config_dir=${CONFIG_DIR:-${HOME}/.config/sketchybar}
  local red=${SKETCHY_RED:?sketchybarrc exports the theme}
  local font="Iosevka Dynamo Nerd:Bold:14.0"

  # The shutdown dialog of loginwindow offers restart, sleep and shut down
  sketchybar --add item session right \
    --set session \
    icon="" \
    icon.color="${red}" \
    icon.padding_left=6 \
    label.drawing=off \
    click_script="osascript -e 'tell application \"loginwindow\" to «event aevtrsdn»'"

  sketchybar --add item battery right \
    --set battery \
    label.font="${font}" \
    update_freq=120 \
    script="${config_dir}/plugins/battery.sh" \
    --subscribe battery power_source_change system_woke

  sketchybar --add item volume right \
    --set volume \
    label.font="${font}" \
    script="${config_dir}/plugins/volume.sh" \
    click_script="open 'x-apple.systempreferences:com.apple.Sound-Settings.extension'" \
    --subscribe volume volume_change

  sketchybar --add item wifi right \
    --set wifi \
    label.drawing=off \
    script="${config_dir}/plugins/wifi.sh" \
    click_script="open 'x-apple.systempreferences:com.apple.wifi-settings-extension'" \
    --subscribe wifi wifi_change system_woke
}

_main "$@"
