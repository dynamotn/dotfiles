#!/usr/bin/env bash
# @file clock.sh
# @brief Declare the clock in the middle of the bar
# @description Declare the date and the time on either side of the centre, as
# the noctalia bar keeps its clock in the middle. They sit left and right of
# the notch (positions q and e), so the built-in display does not hide them.
# Run by sketchybarrc.
set -euo pipefail

#######################################
# @description Declare the date and time items; the time item updates both
# @noargs
#######################################
function _main {
  local config_dir=${CONFIG_DIR:-${HOME}/.config/sketchybar}
  local font="Iosevka Dynamo Nerd:Bold:14.0"
  sketchybar --add item clock.date q \
    --set clock.date icon.drawing=off label.font="${font}" \
    --add item clock.time e \
    --set clock.time \
    icon.drawing=off \
    label.font="${font}" \
    update_freq=30 \
    script="${config_dir}/plugins/clock.sh" \
    --subscribe clock.time system_woke
}

_main "$@"
