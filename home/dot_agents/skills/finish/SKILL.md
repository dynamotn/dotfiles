---
name: finish
description: Use when the user types /finish, or says the work is done and asks to wrap it up, ship it or "go" - proves the change works end to end, simplifies it, and leaves it as reviewed local commits ready for the user to push.
disable-model-invocation: true
---

# Finish the task

The goal: when the user comes back, the change is proven to work, as small
as it can be, and committed locally with an honest report. Never push, open
a pull request, merge, or `chezmoi apply`; those stay the user's.

## Where things stand

- Branch: !`git branch --show-current`
- Changes: !`git status --short`
- Against HEAD: !`git diff --stat HEAD`
- Not pushed yet (or the last ten, without an upstream): !`git log --oneline @{upstream}.. 2>/dev/null || git log --oneline -10`

## 1. Prove it works

Run what the repository already provides, as its `CLAUDE.md` or
`AGENTS.md` names it: the tests that cover the changed files, the linters,
and the pre-commit hooks. Then exercise the change for real where that is
possible: run the CLI, render the template, start the service. A passing
unit test for code that was never run is not proof.

A check that cannot run is reported as such, with the command the user has
to run, never quietly skipped.

## 2. Make it smaller

Review the diff as a reviewer would: duplicated logic that an existing
helper covers, dead branches, comments that restate the code, scope that
crept beyond the ask. In Claude Code, `/simplify` does this pass. Re-run the
checks from step 1 after any change it makes.

## 3. Commit

Follow the repository's own commit conventions (Conventional Commits where
the history uses them). One commit per logical change; a `CHANGELOG.md`
entry in the same commit only when the repository already has one. No agent
attribution trailers.

## 4. Report

What changed, which checks ran and their result, what was not verified and
why, and the next command for the user (usually the push).

## Gotchas

- In the dotfiles, a chezmoi template is checked with
  `chezmoi execute-template --source <this worktree>`; without `--source` it
  renders the main checkout and proves nothing about the change.
- `prek` stashes unstaged changes while it runs. Committing while a test run
  is still going in the background can let that run see the old files; wait
  for it, or re-run after the commit.
- The rtk hook rewrites `git` commands. When a worktree guard refuses a
  rewritten one, a `git add ... && git commit -F - <<'EOF'` form, or a small
  script, gets through.
- A test that was already failing before the change is still reported, named
  as pre-existing, not left out of the report or "fixed" in passing.
