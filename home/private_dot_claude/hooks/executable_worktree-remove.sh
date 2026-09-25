#!/usr/bin/env bash
# WorktreeRemove hook: counterpart to worktree-create.sh. Configuring a
# WorktreeCreate hook replaces the built-in git cleanup too, so remove the
# worktree here.
#
# Exiting non-zero while the directory still exists makes removal fail, so
# fall back to a plain delete and always report success.
set -uo pipefail

input=$(cat)
path=$(jq -r '.worktree_path' <<<"$input")

if [[ -z "$path" || "$path" == "null" || ! -d "$path" ]]; then
  exit 0
fi

# Run git from the main checkout: removing a worktree from inside it fails.
common_dir=$(git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)

if [[ -n "$common_dir" ]]; then
  root=$(dirname "$common_dir")
  git -C "$root" worktree remove --force "$path" >&2 || rm -rf "$path"
  git -C "$root" worktree prune >&2 || true
else
  rm -rf "$path"
fi

exit 0
