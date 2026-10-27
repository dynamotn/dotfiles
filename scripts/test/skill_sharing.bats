setup() {
  load test_helper
}

@test "bundled skills live in the shared ~/.agents store, not Claude's own dir" {
  [ -f "${DOTFILES_DIR}/home/dot_agents/skills/chezmoi-source/SKILL.md" ]
  [ -f "${DOTFILES_DIR}/home/dot_agents/skills/dybatpho/SKILL.md" ]
  [ -f "${DOTFILES_DIR}/home/dot_agents/skills/finish/SKILL.md" ]
  [[ -f "${DOTFILES_DIR}/home/dot_agents/skills/dyai/SKILL.md" ]]
  [ ! -e "${DOTFILES_DIR}/home/private_dot_claude/skills/chezmoi-source" ]
  [ ! -e "${DOTFILES_DIR}/home/private_dot_claude/skills/dybatpho" ]
}

@test "Claude sees the shared skills through chezmoi symlinks into ~/.agents" {
  local base="${DOTFILES_DIR}/home/private_dot_claude/skills"
  [[ "$(cat "${base}/symlink_chezmoi-source")" == "../../.agents/skills/chezmoi-source" ]]
  [[ "$(cat "${base}/symlink_dybatpho")" == "../../.agents/skills/dybatpho" ]]
  [[ "$(cat "${base}/symlink_finish")" == "../../.agents/skills/finish" ]]
  local dyai
  read -r dyai < "${base}/symlink_dyai"
  [[ "${dyai}" == "../../.agents/skills/dyai" ]]
}

@test "the dyai skill is typed, never self-invoked, and lists the crew tools it drives" {
  local skill="${DOTFILES_DIR}/home/dot_agents/skills/dyai/SKILL.md" tool
  grep -qx 'name: dyai' "${skill}"
  grep -qx 'disable-model-invocation: true' "${skill}"
  for tool in crew_run crew_tasks crew_logs crew_review crew_judge crew_fix crew_merge crew_drop; do
    grep -q "\`${tool}\`" "${skill}" || fail "${tool} missing"
    grep -q "\"${tool}\"" "${DOTFILES_DIR}/scripts/lib/dyai_mcp.sh" || fail "${tool} is not a dyai mcp tool"
  done
  # A `!` command that is not allowlisted fails the whole slash command.
  ! grep -q '!`' "${skill}" || fail "the dyai skill injects a shell command"
}

@test "hunk's bundled review skill reaches every agent through ~/.agents" {
  local shared claude
  read -r shared < "${DOTFILES_DIR}/home/dot_agents/skills/symlink_hunk-review"
  read -r claude < "${DOTFILES_DIR}/home/private_dot_claude/skills/symlink_hunk-review"
  [[ "${shared}" == "../../.hunk/skills/hunk-review" ]]
  [[ "${claude}" == "../../.agents/skills/hunk-review" ]]
}
