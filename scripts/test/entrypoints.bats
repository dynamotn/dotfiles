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
  assert_entrypoint_help "home/dot_local/bin/executable_chezmoi-dycrypt.tmpl" "decrypt" "encrypt"
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
  assert_entrypoint_help "home/dot_local/bin/executable_dybird.tmpl" "--profile" "--refresh"
}

@test "dyfox shows profile and refresh help" {
  assert_entrypoint_help "home/dot_local/bin/executable_dyfox.tmpl" "--profile" "--refresh"
}

@test "rbw-pick shows its password and totp commands" {
  assert_entrypoint_help "home/dot_local/bin/executable_rbw-pick.tmpl" "password" "totp"
}

@test "dymonitor shows its feature commands" {
  assert_entrypoint_help "home/dot_local/bin/executable_dymonitor.tmpl" "brightness" "input"
}

# A ddcutil that logs every call and answers like two monitors on a bus that
# also has a device which is not one; monitor 3 never answers
function stub_ddcutil {
  export DDCUTIL_LOG="${BATS_TEST_TMPDIR}/ddcutil.log"
  : > "${DDCUTIL_LOG}"
  cat > "${HOME}/.local/bin/ddcutil" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DDCUTIL_LOG}"
case "$*" in
  "detect --terse")
    printf 'Display 1\n   I2C bus:  /dev/i2c-5\n\nInvalid display\n   I2C bus:  /dev/i2c-7\n\nDisplay 2\n   I2C bus:  /dev/i2c-6\n'
    ;;
  "--display 3 "*) exit 1 ;;
  *"getvcp 10 --brief") printf 'VCP 10 C 60 100\n' ;;
  *"getvcp 60 --brief") printf 'VCP 60 SNC x11\n' ;;
esac
STUB
  chmod +x "${HOME}/.local/bin/ddcutil"
}

@test "dymonitor raises and lowers the brightness of every monitor by the step" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dymonitor"
  render_template "home/dot_local/bin/executable_dymonitor.tmpl" "${rendered}"
  stub_ddcutil

  run bash "${rendered}" brightness --step 5 up
  assert_success
  assert_output --partial "Monitor 1: brightness 60"
  assert_output --partial "Monitor 2: brightness 60"
  assert_file_contains "${DDCUTIL_LOG}" "^--display 1 setvcp 10 + 5$"
  assert_file_contains "${DDCUTIL_LOG}" "^--display 2 setvcp 10 + 5$"
  run bash "${rendered}" brightness down
  assert_success
  assert_file_contains "${DDCUTIL_LOG}" "^--display 1 setvcp 10 - 10$"
}

@test "dymonitor switches the input of one monitor by name or raw value" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dymonitor"
  render_template "home/dot_local/bin/executable_dymonitor.tmpl" "${rendered}"
  stub_ddcutil

  run bash "${rendered}" --display 2 input dp1
  assert_success
  assert_output "Monitor 2: input dp1"
  assert_file_contains "${DDCUTIL_LOG}" "^--display 2 setvcp 60 15$"
  assert_file_not_contains "${DDCUTIL_LOG}" "detect"

  run bash "${rendered}" --display 1 input 0x12
  assert_success
  assert_output "Monitor 1: input hdmi2"
  assert_file_contains "${DDCUTIL_LOG}" "^--display 1 setvcp 60 18$"
}

@test "dymonitor names the input a monitor reports" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dymonitor"
  render_template "home/dot_local/bin/executable_dymonitor.tmpl" "${rendered}"
  stub_ddcutil

  run bash "${rendered}" input
  assert_success
  assert_output --partial "Monitor 1: input hdmi1"
  assert_output --partial "Monitor 2: input hdmi1"
}

@test "dymonitor refuses a value it cannot send" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dymonitor"
  render_template "home/dot_local/bin/executable_dymonitor.tmpl" "${rendered}"
  stub_ddcutil

  run bash "${rendered}" contrast 300
  assert_failure
  assert_output --partial "from 0 to 100"
  run bash "${rendered}" input up
  assert_failure
  run bash "${rendered}" input thunderbolt
  assert_failure
  assert_output --partial "Unknown input source"
  refute [ -s "${DDCUTIL_LOG}" ]
}

@test "dymonitor fails when a monitor does not answer" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dymonitor"
  render_template "home/dot_local/bin/executable_dymonitor.tmpl" "${rendered}"
  stub_ddcutil

  run bash "${rendered}" --display 3 brightness 50
  assert_failure
  assert_output --partial "No answer over DDC/CI from monitor 3"
}

@test "dytoy shows shared installer flags" {
  assert_entrypoint_help "home/dot_local/bin/executable_dytoy.tmpl" "--tool" "--sync"
}

@test "dytoy offers its full-screen interface as a root option only" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"

  run bash "${rendered}" --help
  assert_success
  assert_output --partial "--no-tui"
  assert_output --partial "--jobs"
  run bash "${rendered}" --jobs many --help
  assert_failure
  run bash "${rendered}" binary --help
  assert_success
  refute_output --partial "--no-tui"
}

@test "dytoy keeps the plain run when it has no terminal" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"
  write_tools_yaml << 'EOF'
- name: sample
  method: shell
  content: echo hi
EOF

  run bash "${rendered}" --dry-run < /dev/null
  assert_success
  assert_output --partial "Installed all shell tools"
  refute_output --partial $'\033[?1049h'
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
  write_tools_yaml << 'EOF'
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

@test "dytoy os installs only the packages meant for the release of this OS" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"
  # Only the section of the OS running the test is read.
  write_tools_yaml << 'EOF'
- name: sample
  method: os
  gentoo:
    packages:
      - name: everywhere
      - name: new-release
        releases: [">=24.04"]
      - name: old-release
        releases: ["<24.04"]
  arch:
    packages:
      - name: everywhere
      - name: new-release
        releases: [">=24.04"]
      - name: old-release
        releases: ["<24.04"]
  ubuntu:
    packages:
      - name: everywhere
      - name: new-release
        releases: [">=24.04"]
      - name: old-release
        releases: ["<24.04"]
  alpine:
    packages:
      - name: everywhere
      - name: new-release
        releases: [">=24.04"]
      - name: old-release
        releases: ["<24.04"]
  termux:
    packages:
      - name: everywhere
      - name: new-release
        releases: [">=24.04"]
      - name: old-release
        releases: ["<24.04"]
  macos:
    packages:
      - name: everywhere
      - name: new-release
        releases: [">=24.04"]
      - name: old-release
        releases: ["<24.04"]
EOF

  DYTOY_RELEASE='24.04' run bash "${rendered}" os --dry-run --tool sample --no-check-installed
  assert_success
  assert_output --partial "Installing package everywhere"
  assert_output --partial "Installing package new-release"
  refute_output --partial "Installing package old-release"
}

@test "dytoy fails on a tool whose method is not in the YAML" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"
  write_tools_yaml << 'EOF'
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
  cat > "${HOME}/.config/dytoy/tools.yaml" << EOF
- name: sample
  method: binary
  location: ${HOME}/.local/bin
  github:
    host: github.com
    repo: owner/repo
    version: v1.2.3
    release_asset: sample-linux-amd64
EOF

  # A rehearsal names only the host: dybatpho redacts the rest of a URL it
  # prints, since a download URL can carry a token.
  run bash "${rendered}" binary --dry-run --tool sample --no-check-installed
  assert_success
  assert_output --partial "https://github.com/[redacted]"
  refute_output --partial "owner/repo/releases/download"
  assert_output --partial "Installed binary tool: sample"

  # The URL itself is what curl receives, so a stand-in curl records it.
  local stub_dir="${BATS_TEST_TMPDIR}/stub-bin" args_file="${BATS_TEST_TMPDIR}/curl-args"
  mkdir -p "${stub_dir}"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'printf "%%s\\n" "$@" >> %q\n' "${args_file}"
    cat << 'STUB'
output="" headers=""
while (($#)); do
  case "$1" in
    -o) output="$2"; shift ;;
    -D) headers="$2"; shift ;;
  esac
  shift
done
[[ -z "${headers}" ]] || printf 'HTTP/2 200\r\n\r\n' > "${headers}"
[[ -z "${output}" || "${output}" == /dev/null ]] || printf 'binary\n' > "${output}"
printf '200'
STUB
  } > "${stub_dir}/curl"
  chmod +x "${stub_dir}/curl"
  PATH="${stub_dir}:${PATH}" run bash "${rendered}" binary --tool sample --no-check-installed
  assert_success
  run cat "${args_file}"
  assert_output --partial "https://github.com/owner/repo/releases/download/v1.2.3/sample-linux-amd64"
}

@test "dytoy mise dry-run uses configured backend and version" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"
  write_tools_yaml << 'EOF'
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
  write_tools_yaml << 'EOF'
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

@test "dytoy binary falls back to the top-level version and expands artifact_host" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"
  write_tools_yaml << 'EOF'
- name: sample
  method: binary
  version: v1.2.3
  hook:
    after: echo "hook sees ${DYTOY_VERSION}"
  github:
    repo: owner/repo
    release_asset: sample-%1v-linux-amd64
- name: hosted
  method: binary
  github:
    repo: owner/repo
    version: v2.0.0
    artifact_host: https://cdn.example.com/%v
    release_asset: hosted-%1v
EOF

  run bash "${rendered}" binary --dry-run --tool sample --no-check-installed
  assert_success
  assert_output --partial "Using version v1.2.3"
  assert_output --partial "Release asset is sample-1.2.3-linux-amd64"
  assert_output --partial "export DYTOY_VERSION=v1.2.3"

  local stub_dir="${BATS_TEST_TMPDIR}/stub-bin" args_file="${BATS_TEST_TMPDIR}/curl-args"
  mkdir -p "${stub_dir}"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'printf "%%s\\n" "$@" >> %q\n' "${args_file}"
    cat << 'STUB'
output="" headers=""
while (($#)); do
  case "$1" in
    -o) output="$2"; shift ;;
    -D) headers="$2"; shift ;;
  esac
  shift
done
[[ -z "${headers}" ]] || printf 'HTTP/2 200\r\n\r\n' > "${headers}"
[[ -z "${output}" || "${output}" == /dev/null ]] || printf 'binary\n' > "${output}"
printf '200'
STUB
  } > "${stub_dir}/curl"
  chmod +x "${stub_dir}/curl"
  PATH="${stub_dir}:${PATH}" run bash "${rendered}" binary --tool hosted --no-check-installed
  assert_success
  run cat "${args_file}"
  assert_output --partial "https://cdn.example.com/v2.0.0/hosted-2.0.0"
}

@test "dytoy mise passes its version to the hooks" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"
  write_tools_yaml << 'EOF'
- name: sample
  method: mise
  version: system
  hook:
    before: echo "before ${DYTOY_VERSION}"
EOF

  run bash "${rendered}" mise --dry-run --tool sample --no-check-installed
  assert_success
  assert_output --partial "export DYTOY_VERSION=system"
  assert_output --partial "mise use -g sample@system"
}

@test "dytoy os runs the hook of the section of this OS after the top-level one" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"
  # Every section carries a hook, so the test holds on whichever OS renders it.
  write_tools_yaml << 'EOF'
- name: sample
  method: os
  hook:
    before: echo top-before
  gentoo:
    hook:
      after: echo section-after
  arch:
    hook:
      after: echo section-after
  ubuntu:
    hook:
      after: echo section-after
  alpine:
    hook:
      after: echo section-after
  termux:
    hook:
      after: echo section-after
  macos:
    hook:
      after: echo section-after
EOF

  run bash "${rendered}" os --dry-run --tool sample --no-check-installed
  assert_success
  assert_output --partial "echo top-before"
  assert_output --regexp "Running [a-z]+ after-hook to install sample"
  assert_output --partial "echo section-after"
}

@test "dytoy shell exposes the version to its content" {
  local rendered="${BATS_TEST_TMPDIR}/executable_dytoy"
  render_template "home/dot_local/bin/executable_dytoy.tmpl" "${rendered}"
  write_tools_yaml << 'EOF'
- name: pinned
  method: shell
  version: 1.4.0
  content: echo "installing pinned@${DYTOY_VERSION}"
- name: unpinned
  method: shell
  content: echo "installing unpinned@${DYTOY_VERSION}"
EOF

  run bash "${rendered}" shell --tool pinned --no-check-installed
  assert_success
  assert_output --partial "installing pinned@1.4.0"
  run bash "${rendered}" shell --tool unpinned --no-check-installed
  assert_success
  assert_output --partial "installing unpinned@latest"
}
