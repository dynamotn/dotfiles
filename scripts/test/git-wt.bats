# dyshellint disable=SC2154 DOTFILES_DIR and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  install -m 0755 "${DOTFILES_DIR}/home/dot_local/bin/executable_git-wt" "${HOME}/.local/bin/git-wt"
  export PATH="${HOME}/.local/bin:${PATH}"
  REPO="${BATS_TEST_TMPDIR}/repo"
  git init -q -b main "${REPO}"
  git -C "${REPO}" -c user.name=tester -c user.email=tester@example.com \
    commit -q --allow-empty -m init
}

@test "git wt adds the worktree under .worktrees of the main checkout" {
  run git -C "${REPO}" wt feat/one
  assert_success
  assert [ -d "${REPO}/.worktrees/feat-one" ]
  # From inside a worktree, the next one is still a sibling, not nested.
  run git -C "${REPO}/.worktrees/feat-one" wt two
  assert_success
  assert [ -d "${REPO}/.worktrees/two" ]
}

@test "git wt is not taken over by the alias of a repository" {
  git -C "${REPO}" config alias.wt "!touch '${BATS_TEST_TMPDIR}/hijacked'"
  run git -C "${REPO}" wt safe
  assert_success
  refute [ -e "${BATS_TEST_TMPDIR}/hijacked" ]
  assert [ -d "${REPO}/.worktrees/safe" ]
}
