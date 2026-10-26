# @file dyai_hunk.sh
# @brief Open the working-tree diff side by side in hunk when an agent stops
# @description Every agent's stop hook runs `dyai-hunk` in the project it
# worked in. When that git checkout has changes and no live hunk session
# shows it yet, a `hunk diff --watch` opens in a new zellij floating pane or
# kitty tab, so the agent's edits show up side by side without the agent
# having to remember to open them. `--watch` keeps that one window current
# through later edits. An agent explains its edits by writing hunk's
# agent-context JSON to `dyai-hunk.json` in the checkout's git dir; the window
# loads it as agent notes, and `--watch` reloads it on every write.
# Never fails: a stop hook must not block the agent.
# Sourced (not executed); the caller sources dybatpho first.
# shellcheck shell=bash

#######################################
# @description Open `hunk diff --watch` for the current checkout when it has changes
# @noargs
# @env ZELLIJ string Set inside zellij: open a floating pane there
# @env KITTY_LISTEN_ON string Set inside kitty with remote control: open a tab there
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
  # zellij first: it usually runs inside kitty, and its pane is the one in view.
  if [[ -n "${ZELLIJ-}" ]] && dybatpho::is command zellij; then
    zellij run --floating --close-on-exit --cwd "${repo}" -- "${cmd[@]}" \
      &> /dev/null || true
  elif [[ -n "${KITTY_LISTEN_ON-}" ]] && dybatpho::is command kitty; then
    kitty @ launch --type=tab --keep-focus --cwd="${repo}" "${cmd[@]}" \
      &> /dev/null || true
  fi
  return 0
}
