setup() {
  load test_helper
  # A HOME of its own: the stand-ins below go into its ~/.local/bin
  setup_dotfiles_test_env
  # dyshellint disable=SC2154 DOTFILES_DIR is set by test_helper
  FISH_DIR="${DOTFILES_DIR}/home/private_dot_config/fish"
  command -v fish > /dev/null || skip "fish is not installed"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Run fish code with none of the user's configuration loaded
function _fish {
  local code
  dybatpho::expect_args code -- "$@"
  fish --no-config -c "${code}"
}

# Whether the history hook stores a command line
function _stored {
  local cmdline
  dybatpho::expect_args cmdline -- "$@"
  # The command line goes in as an argument, so no quoting of it can leak
  # into the fish code
  fish --no-config -c "source '${FISH_DIR}/functions/fish_should_add_to_history.fish'
    fish_should_add_to_history \$argv[1]" "${cmdline}"
}

# Every fish source the configuration holds, in FISH_FILES
function _all_fish_files {
  FISH_FILES=("${FISH_DIR}"/conf.d/*.fish "${FISH_DIR}"/functions/*.fish
    "${FISH_DIR}"/completions/*.fish "${FISH_DIR}/setup.fish")
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "every fish file parses" {
  local failures=() file
  _all_fish_files
  for file in "${FISH_FILES[@]}"; do
    fish --no-execute "${file}" 2> /dev/null || failures+=("${file}")
  done
  ((${#failures[@]} == 0)) || fail "$(printf '%s: syntax error\n' "${failures[@]}")"
}

@test "every fish file is formatted by fish_indent" {
  command -v fish_indent > /dev/null || skip "fish_indent is not installed"
  _all_fish_files
  run fish_indent --check "${FISH_FILES[@]}"
  assert_success
}

@test "the rendered config.fish parses and is formatted" {
  command -v chezmoi > /dev/null || skip "chezmoi is not installed"
  # dyshellint disable=SC2154 BATS_TEST_TMPDIR is set by bats
  local rendered="${BATS_TEST_TMPDIR}/config.fish"
  render_template home/private_dot_config/fish/config.fish.tmpl "${rendered}"
  run fish --no-execute "${rendered}"
  assert_success
  if command -v fish_indent > /dev/null; then
    run fish_indent --check "${rendered}"
    assert_success
  fi
}

@test "fish_should_add_to_history stores an ordinary command" {
  run _stored 'git status'
  assert_success
  run _stored 'kubectl get secret my-app -o yaml'
  assert_success
  # dyshellint disable=SC2016 the command line is fish text, not expanded here
  run _stored 'echo $GITHUB_TOKEN | wc -c'
  assert_success
}

@test "fish_should_add_to_history keeps a command typed after a space out" {
  run _stored ' git status'
  assert_failure
}

@test "fish_should_add_to_history keeps a credential assignment out" {
  run _stored 'GH_TOKEN=abc gh pr list'
  assert_failure
  run _stored 'export AWS_SECRET_ACCESS_KEY=abc'
  assert_failure
  run _stored 'set -gx GitLab_Token abc'
  assert_failure
}

@test "fish_should_add_to_history keeps a credential flag out" {
  run _stored 'mysql --password=hunter2 db'
  assert_failure
  run _stored 'vault login --token abc'
  assert_failure
}

@test "fish_should_add_to_history stores a flag with no value after it" {
  run _stored 'gh auth login --with-token < token.txt'
  assert_success
}

@test "fish_should_add_to_history keeps headers, URL passwords and token shapes out" {
  run _stored 'curl -H "Authorization: Bearer abc" https://example.com'
  assert_failure
  run _stored 'git clone https://user:pass@example.com/repo.git'
  assert_failure
  run _stored "git remote add o https://$(printf 'ghp_%s' 'aaaaaaaaaaaaaaaaaaaaaaaa')@github.com/x/y"
  assert_failure
}

@test "shortcuts are abbreviations that expand to the full command" {
  run _fish "source '${FISH_DIR}/conf.d/git.fish'
    source '${FISH_DIR}/conf.d/kubectl.fish'
    abbr --show | string match -e -- 'grh'
    abbr --show | string match -e -- ' kk '"
  assert_success
  assert_line --partial "grh 'git reset --hard'"
  assert_line --partial "kk 'kubectl apply -k'"
}

@test "the replacement aliases stay out of a non-interactive shell" {
  # A stand-in for procs, so the alias would be defined if the guard were missing
  printf '#!/bin/sh\n' > "${HOME}/.local/bin/procs"
  chmod +x "${HOME}/.local/bin/procs"

  run _fish "source '${FISH_DIR}/conf.d/zzz_alternative.fish'; functions -q ps"
  assert_failure
}

# Sets up a repository with a pre-commit config and a prek stand-in that
# records each call
function _prek_repo {
  printf '#!/bin/sh\necho "$*" >> "%s/prek.calls"\n' "${BATS_TEST_TMPDIR}" > "${HOME}/.local/bin/prek"
  chmod +x "${HOME}/.local/bin/prek"
  dybatpho::ensure_dir "${BATS_TEST_TMPDIR}/repo" > /dev/null
  # dyshellint disable=BSG062 test_helper, loaded in setup, unsets GIT_DIR and its kin
  git -C "${BATS_TEST_TMPDIR}/repo" init -q
  touch "${BATS_TEST_TMPDIR}/repo/.pre-commit-config.yaml"
}

# Enter the repository from an interactive shell, where the PWD hooks run
function _cd_into_repo {
  fish --no-config -i -c "source '${FISH_DIR}/conf.d/auto.fish'
    cd '${BATS_TEST_TMPDIR}/repo'" > /dev/null 2>&1
}

@test "entering a repository installs the prek shim" {
  _prek_repo
  _cd_into_repo
  assert_file_contains "${BATS_TEST_TMPDIR}/prek.calls" 'install --hook-type pre-commit'
}

@test "entering a repository leaves an installed prek shim alone" {
  _prek_repo
  mkdir -p "${BATS_TEST_TMPDIR}/repo/.git/hooks"
  printf '#!/bin/sh\nexec prek hook-impl\n' > "${BATS_TEST_TMPDIR}/repo/.git/hooks/pre-commit"
  _cd_into_repo
  assert_file_not_exists "${BATS_TEST_TMPDIR}/prek.calls"
}
