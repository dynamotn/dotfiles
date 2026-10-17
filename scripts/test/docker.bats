setup() {
  load test_helper
  setup_dotfiles_test_env
  DOCKER_SCRIPT="${DOTFILES_DIR}/scripts/docker.sh"
}

@test "docker.sh shows its usage" {
  run bash "${DOCKER_SCRIPT}" --help
  assert_success
  assert_output --partial "Build a toolbox container image"
  assert_output --partial "--log-level"
}

@test "docker.sh names the images it can build when given none" {
  run bash "${DOCKER_SCRIPT}"
  assert_failure
  assert_output --partial "public"
  assert_output --partial "personal-arch"
  assert_output --partial "enterprise-"
}

# The check must come before docker and gomplate are required, or a typo
# reports a missing tool instead of the typo. `${BASH}` keeps the shell bats
# runs in: on macOS the `bash` in /usr/bin is 3.2, which dybatpho rejects.
@test "docker.sh rejects an unknown image without requiring any tool" {
  PATH="/usr/bin:/bin" run "${BASH}" "${DOCKER_SCRIPT}" bogus
  assert_failure
  assert_output --partial "Unknown image bogus"
}

@test "docker.sh rejects an enterprise image with no code" {
  PATH="/usr/bin:/bin" run "${BASH}" "${DOCKER_SCRIPT}" enterprise-
  assert_failure
  assert_output --partial "Unknown image enterprise-"
}

# Runs a snippet with docker/build.sh sourced, which defines its functions
# without building, reading the build secrets from the test directory.
# @arg $1 string Bash code to run
function run_build {
  local snippet
  dybatpho::expect_args snippet -- "$@"
  SECRETS_DIR_UNDER_TEST="${BATS_TEST_TMPDIR}/secrets"
  mkdir -p "${SECRETS_DIR_UNDER_TEST}"
  DOCKER_BUILD_SECRETS_DIR="${SECRETS_DIR_UNDER_TEST}" DYBATPHO_PRIVILEGE=false \
    run --separate-stderr "${BASH}" -c '. "$1"; '"${snippet}" _ "${DOTFILES_DIR}/docker/build.sh"
}

@test "build.sh builds the public image, which has no age secret, with no identity" {
  # It exited 1 without the secret, so the public image could never build.
  run_build '_read_identities'
  assert_success
  assert_output ""
  assert_stderr --partial "without any identity"
}

@test "build.sh reads every identity of the age secret, whatever its passphrase" {
  # Split as words, a passphrase with a space became an identity of its own,
  # and one with a glob character expanded to file names.
  run_build ':'
  printf 'personal=two words\nF1=*\n\n' > "${SECRETS_DIR_UNDER_TEST}/age_passphrases"
  run_build '_read_identities'
  assert_success
  assert_output "personal,F1,"
}
