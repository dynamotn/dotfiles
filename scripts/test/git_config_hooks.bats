# dyshellint disable=SC2154 BATS_TEST_TMPDIR comes from bats
# dyshellint disable=BSG062 test_helper unsets GIT_DIR and its kin
setup() {
  load test_helper
  setup_dotfiles_test_env

  local name
  for name in strip_agent_credit commit_message worktree_submodules worktree_cleanup; do
    render_template "home/private_dot_config/git/scripts/executable_${name}.sh.tmpl" \
      "${BATS_TEST_TMPDIR}/${name}.sh"
  done
  NULL_REF="0000000000000000000000000000000000000000"

  export GIT_CONFIG_GLOBAL="${BATS_TEST_TMPDIR}/gitconfig"
  git config --global user.name "Test"
  git config --global user.email "test@example.com"
  git config --global commit.gpgsign false
  git config --global init.defaultBranch main
  git config --global protocol.file.allow always

  REPO="${BATS_TEST_TMPDIR}/repo"
  git init -q "${REPO}"
  git -C "${REPO}" commit -q --allow-empty -m "seed"
  cd "${REPO}" || return 1
}

@test "strip_agent_credit drops agent trailers and keeps the human ones" {
  local msg="${BATS_TEST_TMPDIR}/msg"
  cat > "${msg}" << 'EOF'
feat: add a thing

Body line.

Co-authored-by: Jane Doe <jane@example.com>
Co-Authored-By: Claude <noreply@anthropic.com>
Assisted-by: Codex
Claude-Session: https://claude.ai/code/session_123
🤖 Generated with [Claude Code](https://claude.com/claude-code)
# ------------------------ >8 ------------------------
+Co-Authored-By: Claude in the diff stays
EOF

  run bash "${BATS_TEST_TMPDIR}/strip_agent_credit.sh" "${msg}"
  assert_success
  assert_output --partial "Dropped the agent attribution lines"
  run cat "${msg}"
  assert_line "Co-authored-by: Jane Doe <jane@example.com>"
  assert_line "+Co-Authored-By: Claude in the diff stays"
  refute_line --partial "noreply@anthropic.com"
  refute_line --partial "Assisted-by"
  refute_line --partial "Claude-Session"
  refute_line --partial "Generated with"
}

@test "strip_agent_credit leaves a clean message untouched" {
  local msg="${BATS_TEST_TMPDIR}/msg"
  printf 'fix: a bug\n\nThe why.\n' > "${msg}"
  cp "${msg}" "${msg}.orig"

  run bash "${BATS_TEST_TMPDIR}/strip_agent_credit.sh" "${msg}"
  assert_success
  assert_output ""
  run diff "${msg}.orig" "${msg}"
  assert_success
}

@test "worktree_submodules checks out what the main checkout has, minus the opted out" {
  local name
  for name in wanted other; do
    git init -q "${BATS_TEST_TMPDIR}/${name}"
    git -C "${BATS_TEST_TMPDIR}/${name}" commit -q --allow-empty -m "${name}"
    git -C "${REPO}" submodule add -q "${BATS_TEST_TMPDIR}/${name}" "${name}"
  done
  git -C "${BATS_TEST_TMPDIR}/wanted" submodule add -q "${BATS_TEST_TMPDIR}/other" nested
  git -C "${BATS_TEST_TMPDIR}/wanted" commit -q -m "nested"
  git -C wanted pull -q
  git -C wanted submodule update -q --init
  git add wanted
  git config -f .gitmodules submodule.other.worktreeInit false
  git add .gitmodules
  git commit -q -m "submodules"
  git worktree add -q .worktrees/task -b task

  cd .worktrees/task || return 1
  local head
  head="$(git rev-parse HEAD)"
  run bash "${BATS_TEST_TMPDIR}/worktree_submodules.sh" "${NULL_REF}" "${head}" 1
  assert_success
  assert_exists wanted/.git
  assert_exists wanted/nested/.git
  assert_not_exists other/.git
}

@test "worktree_submodules does nothing in a plain clone or a branch switch" {
  git config -f .gitmodules submodule.x.path x

  local head
  head="$(git rev-parse HEAD)"
  run bash "${BATS_TEST_TMPDIR}/worktree_submodules.sh" "${NULL_REF}" "${head}" 1
  assert_success
  run bash "${BATS_TEST_TMPDIR}/worktree_submodules.sh" "${head}" "${head}" 1
  assert_success
  assert_output ""
}

@test "worktree_cleanup removes the merged worktree and keeps its branch" {
  git worktree add -q .worktrees/finished -b finished
  git -C .worktrees/finished commit -q --allow-empty -m "work"
  git worktree add -q .worktrees/fresh -b fresh
  git worktree add -q .worktrees/dirty -b dirty finished
  git -C .worktrees/dirty commit -q --allow-empty -m "dirty work"
  touch .worktrees/dirty/untracked
  git merge -q --ff-only dirty

  run bash "${BATS_TEST_TMPDIR}/worktree_cleanup.sh" 0
  assert_success
  assert_output --partial "/.worktrees/dirty: it still holds"
  assert_not_exists .worktrees/finished
  assert_exists .worktrees/fresh
  assert_exists .worktrees/dirty/untracked
  run git branch --list finished
  assert_output --partial "finished"
}

@test "commit_message refuses a long subject and passes a short one" {
  local msg="${BATS_TEST_TMPDIR}/msg"
  printf 'feat: %s\n' "$(printf 'x%.0s' {1..70})" > "${msg}"
  run bash "${BATS_TEST_TMPDIR}/commit_message.sh" "${msg}"
  assert_failure
  assert_output --partial "the limit is 72"

  printf 'fix: a bug\n' > "${msg}"
  run bash "${BATS_TEST_TMPDIR}/commit_message.sh" "${msg}"
  assert_success
}
