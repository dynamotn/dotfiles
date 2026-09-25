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
# reports a missing tool instead of the typo.
@test "docker.sh rejects an unknown image without requiring any tool" {
  PATH="/usr/bin:/bin" run bash "${DOCKER_SCRIPT}" bogus
  assert_failure
  assert_output --partial "Unknown image bogus"
}

@test "docker.sh rejects an enterprise image with no code" {
  PATH="/usr/bin:/bin" run bash "${DOCKER_SCRIPT}" enterprise-
  assert_failure
  assert_output --partial "Unknown image enterprise-"
}
