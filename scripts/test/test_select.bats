# shellcheck disable=SC2154 # DOTFILES_DIR is set by test_helper.bash, the rest by bats
setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/test_select.sh"
  ROOT="${BATS_TEST_TMPDIR}/repo"
  TESTS="${ROOT}/scripts/test"
  mkdir -p "${TESTS}" "${ROOT}/home" "${ROOT}/docs"
  printf '. scripts/lib/network.sh\n' > "${TESTS}/network.bats"
  printf 'run bash hooks/verify-on-stop.sh\n' > "${TESTS}/claude_hooks.bats"
  printf 'run sh scripts/prerequisite.sh\n' > "${TESTS}/prerequisite.bats"
}

@test "test_select::files picks the bats file named after a changed library" {
  run test_select::files "${ROOT}" scripts/lib/network.sh
  assert_success
  assert_output "${TESTS}/network.bats"
}

@test "test_select::files picks a changed bats file itself" {
  : > "${TESTS}/lonely.bats"
  run test_select::files "${ROOT}" scripts/test/lonely.bats
  assert_success
  assert_output "${TESTS}/lonely.bats"
}

@test "test_select::files skips a bats file that was deleted" {
  run test_select::files "${ROOT}" scripts/test/gone.bats
  assert_success
  assert_output ""
}

@test "test_select::files finds a chezmoi source by the name a test spells" {
  run test_select::files "${ROOT}" \
    home/private_dot_claude/hooks/executable_verify-on-stop.sh.tmpl
  assert_success
  assert_output "${TESTS}/claude_hooks.bats"
}

@test "test_select::files lists each file once, sorted, for several paths" {
  run test_select::files "${ROOT}" scripts/prerequisite.sh scripts/lib/network.sh \
    scripts/test/network.bats
  assert_success
  assert_output "${TESTS}/network.bats
${TESTS}/prerequisite.bats"
}

@test "test_select::files asks for the whole suite when what all tests share changed" {
  local path
  for path in scripts/test.sh scripts/test/test_helper.bash scripts/lib/dybatpho; do
    run test_select::files "${ROOT}" scripts/lib/network.sh "${path}"
    assert_success
    assert_output "--all"
  done
}

@test "test_select::files asks for the whole suite for a file no test names" {
  # A test may reach it through a glob, as claude_rules.bats does the rules.
  : > "${ROOT}/home/rule.md.tmpl"
  run test_select::files "${ROOT}" scripts/lib/network.sh home/rule.md.tmpl
  assert_success
  assert_output "--all"
}

@test "test_select::files prints nothing for documentation and deleted files" {
  : > "${ROOT}/docs/setup.md"
  : > "${ROOT}/README.md"
  run test_select::files "${ROOT}" docs/setup.md README.md home/deleted.age
  assert_success
  assert_output ""
}

@test "test_select::files skips what a sandbox masks with a device" {
  ln -s /dev/null "${ROOT}/.bashrc"
  run test_select::files "${ROOT}" .bashrc
  assert_success
  assert_output ""
}
