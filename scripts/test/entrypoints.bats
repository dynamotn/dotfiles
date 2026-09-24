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

@test "every chezmoi-dycrypt subcommand inherits the persistent options" {
  local rendered="${BATS_TEST_TMPDIR}/executable_chezmoi-dycrypt"
  render_template "home/dot_local/bin/executable_chezmoi-dycrypt.tmpl" "${rendered}"

  local command
  for command in encrypt decrypt; do
    run bash "${rendered}" "${command}" --help
    assert_success
    assert_output --partial "--identity-type"
    assert_output --partial "--folder"
    assert_output --partial "--attributes"
    assert_output --partial "--force"
    assert_output --partial "--dry-run"
  done
}

@test "chezmoi-dycrypt encrypts every file it is given and reports the ones it could not" {
  local rendered="${BATS_TEST_TMPDIR}/executable_chezmoi-dycrypt"
  render_template "home/dot_local/bin/executable_chezmoi-dycrypt.tmpl" "${rendered}"
  # The rendered script points at the real repository; a test must never write
  # there, so the sandbox takes its place.
  local sandbox="${BATS_TEST_TMPDIR}/dotfiles"
  dybatpho::ensure_dir "${sandbox}" > /dev/null
  # The libraries the script sources live under that same root.
  ln -s "${DOTFILES_DIR}/scripts" "${sandbox}/scripts"
  sed -i "s|^DYCRYPT_DOTFILES_DIR=.*|DYCRYPT_DOTFILES_DIR='${sandbox}'|" "${rendered}"

  age-keygen -o "$(dybatpho::xdg_config_dir chezmoi)/test.key" 2> /dev/null
  chmod 600 "$(dybatpho::xdg_config_dir chezmoi)/test.key"
  local live="${HOME}/.live"
  dybatpho::ensure_dir "${live}" > /dev/null
  printf 'first\n' > "${live}/first.txt"
  printf 'second\n' > "${live}/second.txt"

  run bash "${rendered}" encrypt -i test -f "${live}" -a create first.txt absent.txt second.txt
  assert_failure
  assert_output --partial "Cannot encrypt 1 file(s): absent.txt"
  # The file after the unusable one still has to be encrypted.
  assert [ -f "${sandbox}/home/private_dot_live/create_encrypted_first.txt.age" ]
  assert [ -f "${sandbox}/home/private_dot_live/create_encrypted_second.txt.age" ]
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

@test "dytoy lists one subcommand per installer method" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"

  run bash "${rendered}" --help
  assert_success
  local method
  for method in os binary mise shell; do
    assert_output --partial "${method}"
  done
}

@test "every dytoy subcommand inherits the persistent options" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"

  local method
  for method in os binary mise shell; do
    run bash "${rendered}" "${method}" --help
    assert_success
    assert_output --partial "--tool"
    assert_output --partial "--essential"
    assert_output --partial "--dry-run"
  done
}

@test "dytoy generates its own shell completion" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"

  local shell
  for shell in bash zsh fish; do
    run bash "${rendered}" completion --shell "${shell}"
    assert_success
    # Every subcommand has to reach the completion, or the shipped fish file
    # would offer less than the CLI accepts.
    local method
    for method in os binary mise shell; do
      assert_output --partial "${method}"
    done
    assert_output --partial "tool"
  done
}

@test "dytoy rejects a completion shell it cannot generate" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"

  run bash "${rendered}" completion --shell tcsh
  assert_failure
}

@test "scz renders as a valid shell script" {
  local rendered="${BATS_TEST_TMPDIR}/executable_scz"
  render_template "home/dot_local/bin/executable_scz.tmpl" "${rendered}"
  run bash -n "${rendered}"
  assert_success
}

@test "dytoy dry-run runs every installer method, os first" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"

  run bash "${rendered}" --dry-run
  assert_success
  local method
  for method in os binary mise shell; do
    assert_output --partial "Installed all ${method} tools"
  done
  # `os` installs the package managers the other methods need, so it leads.
  local os_line binary_line
  os_line="$(printf '%s\n' "${output}" | grep -n 'Installed all os tools' | head -1 | cut -d: -f1)"
  binary_line="$(printf '%s\n' "${output}" | grep -n 'Installed all binary tools' | head -1 | cut -d: -f1)"
  ((os_line < binary_line))
}

@test "dytoy routes a selected tool to its configured method" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"
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
  refute_output --partial "Installed shell tool"
}

@test "dytoy fails on a tool whose method is not in the YAML" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"
  write_tools_yaml <<'EOF'
- name: sample
  other: value
EOF

  run bash "${rendered}" --dry-run --tool sample
  assert_failure
  assert_output --partial "Not found installer method for tool: sample"
}

@test "dytoy binary dry-run builds a release download URL" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"
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

  run bash "${rendered}" binary --dry-run --tool sample --no-check-installed
  assert_success
  assert_output --partial "https://github.com/owner/repo/releases/download/v1.2.3/sample-linux-amd64"
  assert_output --partial "Installed binary tool: sample"
}

@test "dytoy mise dry-run uses configured backend and version" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"
  write_tools_yaml <<'EOF'
- name: sample
  method: mise
  backend: node
  version: 22.0.0
EOF

  run bash "${rendered}" mise --dry-run --tool sample --no-check-installed
  assert_success
  assert_output --partial "mise use -g node@22.0.0"
  assert_output --partial "Installed mise tool: sample"
}

@test "dytoy shell dry-run renders shell content through a temp script" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"
  write_tools_yaml <<'EOF'
- name: sample
  method: shell
  content: |
    echo hello from sample shell tool
EOF

  run bash "${rendered}" shell --dry-run --tool sample --no-check-installed
  assert_success
  assert_output --partial "Running commands to install sample"
  assert_output --partial "hello from sample shell tool"
}
