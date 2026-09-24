setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/chezmoi_attrs.sh"
}

function run_source_path {
  local target attributes
  dybatpho::expect_args target attributes -- "$@"
  local source_path
  chezmoi_attrs::source_path source_path "${target}" "${attributes}" || return 1
  printf '%s' "${source_path}"
}

@test "chezmoi_attrs::source_path maps a home path to the home source tree" {
  run run_source_path "${HOME}/.config/foo/bar.txt" ""
  assert_success
  assert_output "home/private_dot_config/foo/bar.txt"
}

@test "chezmoi_attrs::source_path maps an absolute path outside home to the root source tree" {
  run run_source_path "/etc/hosts" ""
  assert_success
  assert_output "root/etc/hosts"
}

@test "chezmoi_attrs::source_path expands a tilde like a home path" {
  run run_source_path "~/.ssh/config" ""
  assert_success
  assert_output "home/private_dot_ssh/config"
}

@test "chezmoi_attrs::source_path writes attributes in the order chezmoi reads them" {
  run run_source_path "${HOME}/data.sqlite" "encrypted,create"
  assert_success
  assert_output "home/create_encrypted_data.sqlite"
}

@test "chezmoi_attrs::source_path applies attributes to the last component only" {
  run run_source_path "${HOME}/.zen/profile/places.sqlite" "create,encrypted"
  assert_success
  assert_output "home/private_dot_zen/profile/create_encrypted_places.sqlite"
}

@test "chezmoi_attrs::source_path keeps a dotted file private without repeating the attribute" {
  run run_source_path "${HOME}/.netrc" "private,encrypted"
  assert_success
  assert_output "home/encrypted_private_dot_netrc"
}

@test "chezmoi_attrs::source_path rejects a relative target path" {
  run run_source_path "relative/path" ""
  assert_failure
  assert_output --partial "must start with"
}

@test "chezmoi_attrs::source_path rejects an attribute chezmoi does not know" {
  run run_source_path "${HOME}/file" "create,bogus"
  assert_failure
  assert_output --partial "bogus"
}

@test "chezmoi_attrs::validate accepts an empty list" {
  run chezmoi_attrs::validate ""
  assert_success
}
