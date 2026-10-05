#!/usr/bin/env bash
# @file hypr_socket.sh
# @brief Resolve the path of the Hyprland event socket
# @description Resolve the path of the Hyprland event socket for the running
# instance, trying every runtime directory layout in use on this machine, and
# fail when no socket is found.
set -euo pipefail

# @description Print the path of the Hyprland event socket.
# @noargs
# @stdout The absolute path of the `.socket2.sock` event socket.
# @exitcode 1 When no socket matches the running instance.
function _main {
  local uid runtime socket

  if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    printf '%s\n' "hypr_socket.sh: HYPRLAND_INSTANCE_SIGNATURE is unset" >&2
    return 1
  fi

  uid="$(id -u)"
  for runtime in "${XDG_RUNTIME_DIR:-}" "/run/user/${uid}" "/tmp/user-${uid}" "/tmp/user/${uid}"; do
    [[ -n ${runtime} ]] || continue
    socket="${runtime}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket2.sock"
    if [[ -S ${socket} ]]; then
      printf '%s\n' "${socket}"
      return 0
    fi
  done

  printf '%s\n' "hypr_socket.sh: no Hyprland event socket found" >&2
  return 1
}

_main "$@"
