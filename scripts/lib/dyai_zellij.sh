# @file dyai_zellij.sh
# @brief Show a dyai view (hunk, a crew log) in zellij, kitty only as the fallback
# @description Every terminal view dyai opens goes through `dyai_zellij::open`:
# a floating pane inside zellij; outside it, a pane in a background session
# named `dyai` (shown in a kitty tab when no client is attached to it yet);
# and a plain kitty tab only on a machine without zellij. Sourced (not
# executed); the caller sources dybatpho first.
# shellcheck shell=bash

# The background session dyai opens its panes in when it runs outside zellij.
DYAI_ZELLIJ_SESSION="${DYAI_ZELLIJ_SESSION:-dyai}"

#######################################
# @description Tell whether any client is attached to the dyai zellij session
# @noargs
# @exitcode 0 At least one client shows the session
#######################################
function __dyai_zellij_has_client {
  local clients
  local -a lines
  clients="$(zellij --session "${DYAI_ZELLIJ_SESSION}" action list-clients 2> /dev/null)" || return 1
  mapfile -t lines <<< "${clients}"
  # The first line is the column header.
  ((${#lines[@]} > 1))
}

#######################################
# @description Open a command where the user can see it
# @arg $1 string Pane name
# @arg $2 string Working directory
# @arg $3 string Optional `keep`: leave the pane open after the command ends
# @arg $@ string `--`, then the command and its arguments
# @env ZELLIJ string Set inside zellij: open a floating pane there
# @env KITTY_LISTEN_ON string Set inside kitty with remote control
# @env DYAI_VIEWS string `off` opens nothing (the test suites set it)
# @exitcode 0 The view was opened
# @exitcode 1 No terminal could show it; the caller prints the command instead
#######################################
function dyai_zellij::open {
  local name cwd
  dybatpho::expect_args name cwd -- "$@"
  shift 2
  local -a close=(--close-on-exit)
  if [[ "${1-}" == keep ]]; then
    close=()
    shift
  fi
  [[ "${1-}" != -- ]] || shift
  (($# > 0)) || dybatpho::die "dyai_zellij::open needs a command"
  [[ "${DYAI_VIEWS-}" != off ]] || return 1
  if dybatpho::is command zellij; then
    if [[ -n "${ZELLIJ-}" ]]; then
      if zellij run --floating --name "${name}" --cwd "${cwd}" "${close[@]}" -- "$@" &> /dev/null; then
        return 0
      fi
    else
      zellij attach --create-background "${DYAI_ZELLIJ_SESSION}" &> /dev/null || true
      if zellij --session "${DYAI_ZELLIJ_SESSION}" run --name "${name}" --cwd "${cwd}" "${close[@]}" -- "$@" \
        &> /dev/null; then
        # A pane in a session nobody looks at is not a view yet.
        # shellcheck disable=SC2310 # a plain yes/no
        if [[ -n "${KITTY_LISTEN_ON-}" ]] && dybatpho::is command kitty && ! __dyai_zellij_has_client; then
          kitty @ launch --type=tab --keep-focus zellij attach "${DYAI_ZELLIJ_SESSION}" &> /dev/null || true
        fi
        return 0
      fi
    fi
  fi
  if [[ -n "${KITTY_LISTEN_ON-}" ]] && dybatpho::is command kitty; then
    kitty @ launch --type=tab --keep-focus --cwd="${cwd}" "$@" &> /dev/null && return 0
  fi
  return 1
}
