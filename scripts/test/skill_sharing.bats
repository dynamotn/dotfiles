setup() {
  load test_helper
}

@test "bundled skills live in the shared ~/.agents store, not Claude's own dir" {
  # shellcheck disable=SC2154 # DOTFILES_DIR is set by test_helper.bash
  [[ -f "${DOTFILES_DIR}/home/dot_agents/skills/chezmoi-source/SKILL.md" ]]
  [[ -f "${DOTFILES_DIR}/home/dot_agents/skills/finish/SKILL.md" ]]
  [[ -f "${DOTFILES_DIR}/home/dot_agents/skills/learn/SKILL.md" ]]
  [[ ! -e "${DOTFILES_DIR}/home/private_dot_claude/skills/chezmoi-source" ]]
  [[ ! -e "${DOTFILES_DIR}/home/private_dot_claude/skills/dybatpho" ]]
}

@test "Claude sees the shared skills through chezmoi symlinks into ~/.agents" {
  local base="${DOTFILES_DIR}/home/private_dot_claude/skills" skill target
  for skill in chezmoi-source dybatpho finish learn dyai dyai-lead; do
    read -r target < "${base}/symlink_${skill}"
    [[ "${target}" == "../../.agents/skills/${skill}" ]]
  done
}

@test "the dyai skills reach every agent from the dyai submodule" {
  local target skill
  for skill in dyai dyai-lead; do
    read -r target < "${DOTFILES_DIR}/home/dot_agents/skills/symlink_${skill}.tmpl"
    [[ "${target}" == "{{ .chezmoi.sourceDir }}/../scripts/lib/dyai/skills/${skill}" ]]
  done
  [[ -f "${DOTFILES_DIR}/scripts/lib/dyai/skills/dyai/SKILL.md" ]] || skip "the dyai submodule is not checked out"
}

@test "the dybatpho skill reaches every agent from the dybatpho submodule" {
  local target
  read -r target < "${DOTFILES_DIR}/home/dot_agents/skills/symlink_dybatpho.tmpl"
  [[ "${target}" == "{{ .chezmoi.sourceDir }}/../scripts/lib/dybatpho/skills/dybatpho" ]]
  [[ ! -e "${DOTFILES_DIR}/home/dot_agents/skills/dybatpho" ]]
  [[ -f "${DOTFILES_DIR}/scripts/lib/dybatpho/skills/dybatpho/SKILL.md" ]] \
    || skip "the dybatpho submodule does not ship its skill at this commit"
}

@test "hunk's bundled review skill reaches every agent through ~/.agents" {
  local shared claude
  read -r shared < "${DOTFILES_DIR}/home/dot_agents/skills/symlink_hunk-review"
  read -r claude < "${DOTFILES_DIR}/home/private_dot_claude/skills/symlink_hunk-review"
  [[ "${shared}" == "../../.hunk/skills/hunk-review" ]]
  [[ "${claude}" == "../../.agents/skills/hunk-review" ]]
}
