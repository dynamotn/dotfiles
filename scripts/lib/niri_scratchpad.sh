# @file niri_scratchpad.sh
# @brief Toggle a drop-down window on niri, the way hdrop does on Hyprland
# @description niri has no scratchpad, so a window that should drop down is
# parked on the hidden `scratchpad` workspace (declared in
# `niri/workspace.kdl`) and brought back to the focused workspace on demand.
# One key press starts the app when no window of it exists, hides it when it
# has focus, and otherwise pulls it to the focused workspace and focuses it.
# Sourced (not executed); the caller sources dybatpho first.
# shellcheck shell=bash

# Workspace that holds hidden drop-down windows, declared in niri/workspace.kdl.
NIRI_SCRATCHPAD_WORKSPACE="scratchpad"

#######################################
# @description Show, hide or start the drop-down window of one app
# @arg $1 string App id of the window, matched exactly
# @arg $@ string Command that starts the app, run when no window of it exists
# @exitcode 0 The window was toggled or the app started
# @exitcode 1 niri could not be reached
#######################################
function niri_scratchpad::toggle {
  local app_id
  dybatpho::expect_args app_id -- "$@"
  shift
  local windows window id focused workspaces workspace
  windows="$(niri msg -j windows)"
  # dyshellint disable=SC2016 $id is a jq variable, bound by --arg
  window="$(dybatpho::json_query - 'first(.[] | select(.app_id == $id)) | "\(.id) \(.is_focused)"' \
    -r --arg id "${app_id}" <<< "${windows}")"
  if [[ -z "${window}" ]]; then
    niri msg action spawn -- "$@"
    return
  fi
  read -r id focused <<< "${window}"
  if [[ "${focused}" == "true" ]]; then
    niri msg action move-window-to-workspace --window-id "${id}" --focus false \
      "${NIRI_SCRATCHPAD_WORKSPACE}"
    return
  fi
  # An index names a workspace of the focused monitor, which is where it goes.
  workspaces="$(niri msg -j workspaces)"
  workspace="$(dybatpho::json_query - 'first(.[] | select(.is_focused)) | .idx' -r \
    <<< "${workspaces}")"
  niri msg action move-window-to-workspace --window-id "${id}" --focus false \
    "${workspace}"
  niri msg action focus-window --id "${id}"
}
