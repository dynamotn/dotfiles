#!/usr/bin/env bash
# @file workspaces.sh
# @brief Highlight the sketchybar item of the focused aerospace workspace
# @description Highlight the sketchybar item of the focused aerospace
# workspace and dim every other one. Invoked by sketchybar with the workspace
# id as its only argument.
set -euo pipefail

# sketchybar exports these to every item script it runs.
config_dir=${CONFIG_DIR:-${HOME}/.config/sketchybar}
item_name=${NAME:?sketchybar sets NAME for item scripts}

theme_file="${config_dir}/themes/catppuccin.sh"
[[ -r "${theme_file}" ]] || exit 1
# The theme is a chezmoi template, so there is no file to follow here.
# shellcheck source=/dev/null
. "${theme_file}"
focused_label=${SKETCHY_MAUVE:?}
focused_background=${SKETCHY_SURFACE_2:?}
idle_label=${SKETCHY_SUBTEXT_0:?}
idle_background=${SKETCHY_SURFACE_0:?}

workspace_id=$1
focus_workspace_ids="${FOCUSED_WORKSPACE:-}"
if [[ -z "${focus_workspace_ids}" ]]; then
  focus_workspace_ids=$(aerospace list-workspaces --focused)
fi

if [[ "${workspace_id}" == "${focus_workspace_ids}" ]]; then
  sketchybar --set "${item_name}" \
    label.color="${focused_label}" \
    background.color="${focused_background}"
else
  sketchybar --set "${item_name}" background.drawing=off \
    label.color="${idle_label}" \
    background.color="${idle_background}"
fi
