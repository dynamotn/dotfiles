setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/misc.sh"
}

function run_replace_version {
  local input version
  dybatpho::expect_args input version -- "$@"
  printf '%s' "$input" | misc::replace_version "$version"
}

@test "misc::replace_version expands version placeholders" {
  run run_replace_version 'tool-%v-%1v' 'v1.2.3'
  assert_success
  assert_output 'tool-v1.2.3-1.2.3'
}

@test "misc::replace_version keeps a tag without a leading v whole" {
  run run_replace_version 'tool-%v-%1v' '1.2.3'
  assert_success
  assert_output 'tool-1.2.3-1.2.3'
}

@test "misc::replace_version takes a tag holding sed metacharacters literally" {
  run run_replace_version $'a-%v\nb-%1v' 'cli/v1&2'
  assert_success
  assert_output $'a-cli/v1&2\nb-cli/v1&2'
}

@test "misc::install_tool dispatches through dytoy when the command is missing" {
  export DRY_RUN='true'

  # A name no system ships: macOS has a `sample` command of its own.
  run misc::install_tool dytoy-missing-tool
  assert_success
  assert_output --partial "${HOME}/.local/bin/dytoy -t dytoy-missing-tool"
}
