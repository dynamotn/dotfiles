setup() {
  load test_helper
}

@test "bundled skills live in the shared ~/.agents store, not Claude's own dir" {
  [ -f "${DOTFILES_DIR}/home/dot_agents/skills/chezmoi-source/SKILL.md" ]
  [ -f "${DOTFILES_DIR}/home/dot_agents/skills/dybatpho/SKILL.md" ]
  [ ! -e "${DOTFILES_DIR}/home/private_dot_claude/skills/chezmoi-source" ]
  [ ! -e "${DOTFILES_DIR}/home/private_dot_claude/skills/dybatpho" ]
}

@test "Claude sees the shared skills through chezmoi symlinks into ~/.agents" {
  local base="${DOTFILES_DIR}/home/private_dot_claude/skills"
  [[ "$(cat "${base}/symlink_chezmoi-source")" == "../../.agents/skills/chezmoi-source" ]]
  [[ "$(cat "${base}/symlink_dybatpho")" == "../../.agents/skills/dybatpho" ]]
}
