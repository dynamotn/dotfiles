# @file dyai_hunk.sh
# @brief Open the working-tree diff side by side in hunk when an agent stops
# @description Every agent's stop hook runs `dyai-hunk` in the project it
# worked in. When that git checkout has changes and no live hunk session
# shows it yet, a `hunk diff --watch` opens through `dyai_zellij::open` (a
# zellij pane, kitty only without zellij), so the agent's edits show up side
# by side without the agent having to remember to open them. `--watch` keeps
# that one window current through later edits. An agent explains its edits by
# writing hunk's agent-context JSON to `dyai-hunk.json` in the checkout's git
# dir; the window loads it as agent notes, and `--watch` reloads it on every
# write. Never fails: a stop hook must not block the agent.
# Sourced (not executed) after dyai_zellij.sh; the caller sources dybatpho first.
# shellcheck shell=bash

#######################################
# @description Open `hunk diff --watch` for the current checkout when it has changes
# @noargs
# @exitcode 0 Always
#######################################
function dyai_hunk::main {
  dybatpho::is command hunk || return 0
  local repo changes sidecar
  repo="$(git rev-parse --show-toplevel 2> /dev/null)" || return 0
  changes="$(git -C "${repo}" status --porcelain 2> /dev/null)" || return 0
  [[ -n "${changes}" ]] || return 0
  # One window per checkout: a live session already follows it.
  ! hunk session get --repo "${repo}" &> /dev/null || return 0
  local -a cmd=(hunk diff --watch)
  # Inside the git dir, so the notes never show up as a change themselves.
  # Created empty when missing: `--watch` only follows a sidecar it opened with.
  sidecar="$(git -C "${repo}" rev-parse --path-format=absolute \
    --git-path dyai-hunk.json 2> /dev/null)" || sidecar=""
  if [[ -n "${sidecar}" ]] && { [[ -f "${sidecar}" ]] || echo '{}' > "${sidecar}"; } 2> /dev/null; then
    cmd+=(--agent-context "${sidecar}")
  fi
  # shellcheck disable=SC2310 # no terminal to show it in is not an error here
  dyai_zellij::open hunk "${repo}" -- "${cmd[@]}" || true
  return 0
}
