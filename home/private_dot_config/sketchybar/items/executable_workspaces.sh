#!/usr/bin/env bash
# @file workspaces.sh
# @brief Declare the hidden item that keeps the workspace items in sync
# @description Declare one hidden `workspaces` item. Its script
# (plugins/workspaces.sh) adds, removes and places the per-workspace items, so
# it runs on every workspace change, display change and wake, and once at
# startup through `sketchybar --update`. Run by sketchybarrc.
set -euo pipefail

#######################################
# @description Declare the event and the hidden controller item
# @noargs
#######################################
function _main {
  local config_dir=${CONFIG_DIR:-${HOME}/.config/sketchybar}
  sketchybar --add event aerospace_workspace_change
  # updates=on, or a hidden item never runs its script
  sketchybar --add item workspaces left \
    --set workspaces \
    drawing=off \
    updates=on \
    script="${config_dir}/plugins/workspaces.sh" \
    --subscribe workspaces aerospace_workspace_change display_change system_woke
}

_main "$@"
