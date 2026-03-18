setup() {
  load test_helper
  setup_dotfiles_test_env
}

function assert_entrypoint_help {
  local relative_path first_snippet second_snippet
  dybatpho::expect_args relative_path first_snippet second_snippet -- "$@"
  local rendered="${BATS_TEST_TMPDIR}/$(basename "${relative_path}" .tmpl)"
  render_template "${relative_path}" "${rendered}"
  run bash "${rendered}" --help
  assert_success
  assert_output --partial "${first_snippet}"
  assert_output --partial "${second_snippet}"
}

@test "chezmoi-dycrypt shows subcommand help" {
  assert_entrypoint_help     "home/dot_local/bin/executable_chezmoi-dycrypt.tmpl"     "decrypt"     "encrypt"
}

@test "dybird shows profile and refresh help" {
  assert_entrypoint_help     "home/dot_local/bin/executable_dybird.tmpl"     "--profile"     "--refresh"
}

@test "dyfox shows profile and refresh help" {
  assert_entrypoint_help     "home/dot_local/bin/executable_dyfox.tmpl"     "--profile"     "--refresh"
}

@test "dytoy shows shared installer flags" {
  assert_entrypoint_help     "home/dot_local/bin/executable_dytoy.tmpl"     "--tool"     "--sync"
}

@test "dytoy_binary shows binary installer flags" {
  assert_entrypoint_help     "home/dot_local/bin/executable_dytoy_binary.tmpl"     "--tool"     "--list"
}

@test "dytoy_mise shows mise installer flags" {
  assert_entrypoint_help     "home/dot_local/bin/executable_dytoy_mise.tmpl"     "--tool"     "--essential"
}

@test "dytoy_os shows os installer flags" {
  assert_entrypoint_help     "home/dot_local/bin/executable_dytoy_os.tmpl"     "--tool"     "--sync"
}

@test "dytoy_shell shows shell installer flags" {
  assert_entrypoint_help     "home/dot_local/bin/executable_dytoy_shell.tmpl"     "--tool"     "--essential"
}

@test "scz renders as a valid shell script" {
  local rendered="${BATS_TEST_TMPDIR}/executable_scz"
  render_template "home/dot_local/bin/executable_scz.tmpl" "${rendered}"
  run bash -n "${rendered}"
  assert_success
}

@test "dytoy dry-run dispatches to all installer entrypoints" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"

  run bash "${rendered}" --dry-run
  assert_success
  assert_output --partial "${HOME}/.local/bin/dytoy_os"
  assert_output --partial "${HOME}/.local/bin/dytoy_binary"
  assert_output --partial "${HOME}/.local/bin/dytoy_mise"
  assert_output --partial "${HOME}/.local/bin/dytoy_shell"
}

@test "dytoy routes a selected tool to its configured method" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"
  write_tools_yaml <<'EOF'
- name: sample
  method: binary
EOF

  run bash "${rendered}" --dry-run --tool sample
  assert_success
  assert_output --partial "${HOME}/.local/bin/dytoy_binary"
  assert_output --partial "-t sample"
  refute_output --partial "${HOME}/.local/bin/dytoy_shell"
}

@test "dytoy_binary dry-run builds a release download URL" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy_binary"
  render_template "home/dot_local/bin/executable_dytoy_binary.tmpl" "${rendered}"
  cat > "${HOME}/.config/dytoy/tools.yaml" <<EOF
- name: sample
  method: binary
  location: ${HOME}/.local/bin
  github:
    host: github.com
    repo: owner/repo
    version: v1.2.3
    release_asset: sample-linux-amd64
EOF

  run bash "${rendered}" --dry-run --tool sample --no-check-installed
  assert_success
  assert_output --partial "https://github.com/owner/repo/releases/download/v1.2.3/sample-linux-amd64"
  assert_output --partial "Installed binary tool: sample"
}

@test "dytoy_mise dry-run uses configured backend and version" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy_mise"
  render_template "home/dot_local/bin/executable_dytoy_mise.tmpl" "${rendered}"
  write_tools_yaml <<'EOF'
- name: sample
  method: mise
  backend: node
  version: 22.0.0
EOF

  run bash "${rendered}" --dry-run --tool sample --no-check-installed
  assert_success
  assert_output --partial "mise use -g node@22.0.0"
  assert_output --partial "Installed mise tool: sample"
}

@test "dytoy_shell dry-run renders shell content through a temp script" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy_shell"
  render_template "home/dot_local/bin/executable_dytoy_shell.tmpl" "${rendered}"
  write_tools_yaml <<'EOF'
- name: sample
  method: shell
  content: |
    echo hello from sample shell tool
EOF

  run bash "${rendered}" --dry-run --tool sample --no-check-installed
  assert_success
  assert_output --partial "Running commands to install sample"
  assert_output --partial "hello from sample shell tool"
}
