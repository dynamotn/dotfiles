#!/usr/bin/env bash
# @file workspaces.sh
# @brief Declare one sketchybar item per aerospace workspace
# @description Declare one sketchybar item per aerospace workspace, each with
# its own icon and a click action that switches to that workspace.
sketchybar --add event aerospace_workspace_change

#######################################
# @description Map a workspace id to its icon
# @arg $1 string Workspace id
# @stdout Icon of the workspace, empty for an unknown id
#######################################
function get_icon {
  case "$1" in
    1) printf "" ;; # Term
    2) printf "" ;; # Web
    3) printf "" ;; # Mail
    4) printf "" ;; # Doc
    5) printf "" ;; # Chat
    6) printf "" ;; # Media
    7) printf "" ;; # Game
    8) printf "" ;; # Sys
    9) printf "" ;; # Misc
    0) printf "" ;; # Sec
    *) printf "" ;;
  esac
}

workspace_ids=()
readarray -t workspace_ids < <(aerospace list-workspaces --all)
for workspace_id in "${workspace_ids[@]}"; do
  workspace_icon=$(get_icon "${workspace_id}")

  sketchybar --add item "workspace.${workspace_id}" left
  sketchybar --subscribe "workspace.${workspace_id}" aerospace_workspace_change
  sketchybar --set "workspace.${workspace_id}" \
    background.corner_radius=5 \
    background.height=20 \
    background.color="${SKETCHY_SURFACE_0}" \
    label.color="${SKETCHY_SUBTEXT_0}" \
    label="${workspace_icon} " \
    click_script="aerospace workspace ${workspace_id}" \
    script="${CONFIG_DIR}/plugins/workspaces.sh ${workspace_id}"
done
