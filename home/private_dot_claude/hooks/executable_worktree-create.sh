#!/usr/bin/env bash
# WorktreeCreate hook: place worktrees in <repo>/.worktrees/<name> instead of
# the built-in <repo>/.claude/worktrees/<name>.
#
# Claude Code reads the last line of stdout as the worktree path, so every
# other message must go to stderr.
set -euo pipefail

input=$(cat)
name=$(jq -r '.name' <<<"$input")
cwd=$(jq -r '.cwd' <<<"$input")

if [ -z "$name" ] || [ "$name" = "null" ]; then
  echo "worktree-create: no name in hook input" >&2
  exit 1
fi

# Resolve the main checkout, not the current worktree: --git-common-dir points
# at the shared .git directory even when invoked from inside a linked worktree.
common_dir=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir)
root=$(dirname "$common_dir")

dir="$root/.worktrees/$name"
branch="worktree-$name"

# Reusing a name reopens the existing worktree, matching the built-in behavior.
if [ -d "$dir" ]; then
  echo "worktree-create: reusing $dir" >&2
  echo "$dir"
  exit 0
fi

mkdir -p "$root/.worktrees"

if git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
  git -C "$root" worktree add "$dir" "$branch" >&2
else
  # Match the default "fresh" base: the remote's default branch, falling back
  # to local HEAD when there is no remote or it has not been fetched.
  base=$(git -C "$root" rev-parse --verify --quiet origin/HEAD || true)
  [ -n "$base" ] || base=HEAD
  git -C "$root" worktree add -b "$branch" "$dir" "$base" >&2
fi

echo "$dir"
