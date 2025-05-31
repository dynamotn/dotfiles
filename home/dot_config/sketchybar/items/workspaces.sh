#!/usr/bin/env bash
sketchybar --add event aerospace_workspace_change

get_icon() {
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

for workspace_id in $(aerospace list-workspaces --all); do
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
