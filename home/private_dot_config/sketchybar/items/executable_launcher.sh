#!/usr/bin/env bash
# @file launcher.sh
# @brief Declare the launcher button at the start of the bar
# @description Declare the launcher that opens the Apps grid, the first widget
# on the left as on the noctalia bar. Run by sketchybarrc before the
# workspaces, so it stays left of them.
set -euo pipefail

#######################################
# @description Declare the launcher item
# @noargs
#######################################
function _main {
  local mauve=${SKETCHY_MAUVE:?sketchybarrc exports the theme}
  sketchybar --add item launcher left \
    --set launcher \
    icon="" \
    icon.font="Iosevka Dynamo Nerd:Bold:18.0" \
    icon.color="${mauve}" \
    icon.padding_right=6 \
    label.drawing=off \
    click_script="open -a Apps"
}

_main "$@"
