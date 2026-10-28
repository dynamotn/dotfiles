setup() {
  load test_helper
}

@test "bundled skills live in the shared ~/.agents store, not Claude's own dir" {
  [ -f "${DOTFILES_DIR}/home/dot_agents/skills/chezmoi-source/SKILL.md" ]
  [ -f "${DOTFILES_DIR}/home/dot_agents/skills/dybatpho/SKILL.md" ]
  [ -f "${DOTFILES_DIR}/home/dot_agents/skills/finish/SKILL.md" ]
  [ -f "${DOTFILES_DIR}/home/dot_agents/skills/learn/SKILL.md" ]
  [ ! -e "${DOTFILES_DIR}/home/private_dot_claude/skills/chezmoi-source" ]
  [ ! -e "${DOTFILES_DIR}/home/private_dot_claude/skills/dybatpho" ]
}

@test "Claude sees the shared skills through chezmoi symlinks into ~/.agents" {
  local base="${DOTFILES_DIR}/home/private_dot_claude/skills"
  [[ "$(cat "${base}/symlink_chezmoi-source")" == "../../.agents/skills/chezmoi-source" ]]
  [[ "$(cat "${base}/symlink_dybatpho")" == "../../.agents/skills/dybatpho" ]]
  [[ "$(cat "${base}/symlink_finish")" == "../../.agents/skills/finish" ]]
  [[ "$(cat "${base}/symlink_learn")" == "../../.agents/skills/learn" ]]
  local dyai
  read -r dyai < "${base}/symlink_dyai"
  [[ "${dyai}" == "../../.agents/skills/dyai" ]]
}

@test "the dyai skill reaches every agent from the dyai submodule" {
  local target
  read -r target < "${DOTFILES_DIR}/home/dot_agents/skills/symlink_dyai.tmpl"
  [[ "${target}" == "{{ .chezmoi.sourceDir }}/../scripts/lib/dyai/skills/dyai" ]]
  [[ -f "${DOTFILES_DIR}/scripts/lib/dyai/skills/dyai/SKILL.md" ]] || skip "the dyai submodule is not checked out"
}

@test "hunk's bundled review skill reaches every agent through ~/.agents" {
  local shared claude
  read -r shared < "${DOTFILES_DIR}/home/dot_agents/skills/symlink_hunk-review"
  read -r claude < "${DOTFILES_DIR}/home/private_dot_claude/skills/symlink_hunk-review"
  [[ "${shared}" == "../../.hunk/skills/hunk-review" ]]
  [[ "${claude}" == "../../.agents/skills/hunk-review" ]]
}
