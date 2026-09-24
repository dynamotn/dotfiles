# Changelog

All notable changes to this repository are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **Shared AI agent conventions** — `home/.chezmoitemplates/ai/git-conventions.md.tmpl`
  defines the git rules every AI agent must follow: short one-line commit
  subjects, a `CHANGELOG.md` entry in the same commit as the change, and no
  agent attribution trailers such as `Co-Authored-By:`.
- **Global instruction files for more coding agents**, all generated from the
  same shared templates so they stay in sync: Gemini CLI (`~/.gemini/GEMINI.md`),
  Codex (`~/.codex/AGENTS.md`), Qwen Code (`~/.qwen/QWEN.md`), OpenCode
  (`~/.config/opencode/AGENTS.md`), Crush (`~/.config/crush/CRUSH.md`), Amp
  (`~/.config/amp/AGENTS.md`), Goose (`~/.config/goose/.goosehints`), Hermes
  (`~/.hermes/SOUL.md`), and a shared fallback at `~/.config/AGENTS.md`.
- **Worktrees in `.worktrees/`** — `WorktreeCreate` and `WorktreeRemove` hooks in
  the Claude Code settings put new worktrees in `<repo>/.worktrees/<name>`
  instead of `<repo>/.claude/worktrees/<name>`, and clean them up again.

### Changed

- The global git ignore now ignores `.worktrees/`, so worktrees don't show up as
  untracked files in the repository they live in.
