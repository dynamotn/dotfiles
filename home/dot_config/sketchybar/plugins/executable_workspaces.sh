#!/usr/bin/env bash
source "${CONFIG_DIR}/themes/catppuccin-macchiato.sh"

workspace_id=$1
focus_workspace_ids="${FOCUSED_WORKSPACE}"
if [[ -z "${focus_workspace_ids}" ]]; then
  focus_workspace_ids=$(aerospace list-workspaces --focused)
fi

if [ "${workspace_id}" = "${focus_workspace_ids}" ]; then
  sketchybar --set "$NAME" \
    label.color="${SKETCHY_MAUVE}" \
    background.color="${SKETCHY_SURFACE_2}"
else
  :
  sketchybar --set "$NAME" background.drawing=off \
    label.color="${SKETCHY_SUBTEXT_0}" \
    background.color="${SKETCHY_SURFACE_0}"
fi
