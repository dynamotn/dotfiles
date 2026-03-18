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

@test "misc::install_tool dispatches through dytoy when the command is missing" {
  export DRY_RUN='true'

  run misc::install_tool sample
  assert_success
  assert_output --partial "${HOME}/.local/bin/dytoy -t sample"
}
