setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/dytoy.sh"
}

function _pipe_replace_version {
  local input version
  dybatpho::expect_args input version -- "$@"
  printf '%s' "$input" | misc::replace_version "$version"
}

@test "dytoy::get_yaml reads scalar and list fields from tools.yaml" {
  write_tools_yaml << 'EOF'
- name: sample
  method: binary
  dependencies:
    - helper
  params:
    - --tool-option=extras=render
    - --tool-option=uvx_args=--python 3.12
  github:
    repo: owner/repo
EOF

  run dytoy::get_yaml sample method
  assert_success
  assert_output 'binary'

  run dytoy::get_yaml sample dependencies
  assert_success
  assert_output 'helper'

  run dytoy::get_yaml sample params
  assert_success
  assert_output $'--tool-option=extras=render\n--tool-option=uvx_args=--python 3.12'
}

@test "dytoy::create_script writes a runnable temp script and dytoy::run_script clears it" {
  local script_path="${BATS_TEST_TMPDIR}/sample.sh"
  local result_path="${BATS_TEST_TMPDIR}/result"
  . "${DOTFILES_DIR}/scripts/lib/misc.sh"

  run dytoy::create_script sample "${script_path}" "echo done > '${result_path}'" commands
  assert_success
  assert_file_exist "${script_path}"
  run cat "${script_path}"
  assert_success
  assert_output --partial 'Running commands to install sample'

  run dytoy::run_script "${script_path}"
  assert_success
  assert_file_exist "${result_path}"
  run cat "${result_path}"
  assert_success
  assert_output 'done'
  run cat "${script_path}"
  assert_success
  assert_output ''
}

@test "dytoy::run_script keeps the temp files registered before the hook" {
  local script_path="${BATS_TEST_TMPDIR}/sample.sh"
  local temp_file
  dybatpho::create_temp temp_file ".tmp"
  local before="${#DYBATPHO_CLEANUP_PATHS[@]}"
  dytoy::create_script sample "${script_path}" "true" commands
  dytoy::run_script "${script_path}"
  assert_equal "${#DYBATPHO_CLEANUP_PATHS[@]}" "${before}"
}

@test "dytoy::create_script exports the version of the tool to the script" {
  local script_path="${BATS_TEST_TMPDIR}/sample.sh"
  local result_path="${BATS_TEST_TMPDIR}/result"

  run dytoy::create_script sample "${script_path}" \
    "echo \"\${DYTOY_VERSION}\" > '${result_path}'" commands 'v1.2.3 rc'
  assert_success
  run dytoy::run_script "${script_path}"
  assert_success
  run cat "${result_path}"
  assert_output 'v1.2.3 rc'

  run dytoy::create_script sample "${script_path}" "echo none" commands
  assert_success
  run cat "${script_path}"
  refute_output --partial 'DYTOY_VERSION'
}

# @description Write a tool whose hooks each append their own name to `$1`
function _write_hooked_tool {
  local log
  dybatpho::expect_args log -- "$@"
  write_tools_yaml << EOF
- name: sample
  method: os
  hook:
    before: echo top-before >> '${log}'
    after: echo "top-after \${DYTOY_VERSION:-}" >> '${log}'
  arch:
    packages:
      - name: sample
    hook:
      before: echo arch-before >> '${log}'
      after: echo arch-after >> '${log}'
  ubuntu:
    packages:
      - name: sample
  flatpak:
    packages:
      - name: org.example.Sample
    hook:
      before: echo flatpak-before >> '${log}'
EOF
}

@test "dytoy::run_hook runs the top-level hook without an OS section" {
  local log="${BATS_TEST_TMPDIR}/hooks"
  _write_hooked_tool "${log}"

  run dytoy::run_hook sample before
  assert_success
  run dytoy::run_hook sample after "" v1.2.3
  assert_success
  run cat "${log}"
  assert_success
  assert_output "$(printf 'top-before\ntop-after v1.2.3')"
}

@test "dytoy::run_hook runs the OS hook inside the top-level one" {
  local log="${BATS_TEST_TMPDIR}/hooks"
  _write_hooked_tool "${log}"

  run dytoy::run_hook sample before arch
  assert_success
  run dytoy::run_hook sample after arch
  assert_success
  run cat "${log}"
  assert_success
  assert_output "$(printf 'top-before\narch-before\narch-after\ntop-after ')"
}

@test "dytoy::run_hook skips an OS section without a hook" {
  local log="${BATS_TEST_TMPDIR}/hooks"
  _write_hooked_tool "${log}"

  run dytoy::run_hook sample before ubuntu
  assert_success
  run dytoy::run_hook sample after termux
  assert_success
  run cat "${log}"
  assert_success
  assert_output "$(printf 'top-before\ntop-after ')"
}

@test "dytoy::run_section_hook runs only the hook of the section it names" {
  local log="${BATS_TEST_TMPDIR}/hooks"
  _write_hooked_tool "${log}"

  run dytoy::run_section_hook sample before flatpak
  assert_success
  run dytoy::run_section_hook sample after flatpak
  assert_success
  run cat "${log}"
  assert_success
  assert_output 'flatpak-before'
}

@test "dytoy::run_section_hook names the section in the rendered script" {
  local calls="${BATS_TEST_TMPDIR}/hook-calls"
  function dytoy::get_yaml { printf 'echo %s\n' "$2"; }
  function dytoy::create_script { printf 'create %s [%s] %s [%s]\n' "$1" "$3" "$4" "$5" >> "${calls}"; }
  function dytoy::run_script { printf 'run\n' >> "${calls}"; }

  run dytoy::run_section_hook sample after arch v1.0.0
  assert_success
  run dytoy::run_section_hook sample before
  assert_success
  run cat "${calls}"
  assert_success
  assert_line --index 0 'create sample [echo arch.hook.after] arch after-hook [v1.0.0]'
  assert_line --index 1 'run'
  assert_line --index 2 'create sample [echo hook.before] before-hook []'
  assert_line --index 3 'run'
}

@test "dytoy::run_section_hook renders an empty hook when the specification cannot be read" {
  local calls="${BATS_TEST_TMPDIR}/hook-calls"
  function dytoy::get_yaml { return 1; }
  function dytoy::create_script { printf 'create [%s]\n' "$3" >> "${calls}"; }
  function dytoy::run_script { printf 'run\n' >> "${calls}"; }

  run dytoy::run_section_hook sample after "" v1.0.0
  assert_success
  run cat "${calls}"
  assert_success
  assert_line --index 0 "create []"
  assert_line --index 1 "run"
}

@test "dytoy::run_hook refuses an unknown stage" {
  run dytoy::run_hook sample during
  assert_failure
  assert_output --partial 'Unknown hook stage: during'

  run dytoy::run_section_hook sample during arch
  assert_failure
  assert_output --partial 'Unknown hook stage: during'
}

@test "dytoy::get_version falls back to latest" {
  write_tools_yaml << 'EOF'
- name: pinned
  method: shell
  version: 1.4.0
  github:
    version: v2.0.0
- name: unpinned
  method: shell
EOF

  run dytoy::get_version pinned
  assert_output '1.4.0'
  run dytoy::get_version pinned github.version
  assert_output 'v2.0.0'
  run dytoy::get_version unpinned
  assert_output 'latest'
}

@test "dytoy::package_checker and checked_package_name name what an OS checks" {
  run dytoy::package_checker termux
  assert_output 'apt'
  run dytoy::package_checker fedora
  assert_failure

  run dytoy::checked_package_name arch neovim HEAD
  assert_output 'neovim-git'
  run dytoy::checked_package_name macos go 1.22
  assert_output 'go@1.22'
  run dytoy::checked_package_name macos neovim null
  assert_output 'neovim'
  run dytoy::checked_package_name gentoo app-editors/neovim HEAD
  assert_output 'app-editors/neovim'
}

@test "dytoy::get_yaml_or falls back on an unset or empty field, even to an empty default" {
  write_tools_yaml << 'EOF'
- name: sample
  method: binary
  location: /opt/bin
  backend: ""
EOF

  run dytoy::get_yaml_or sample location /default
  assert_output '/opt/bin'
  run dytoy::get_yaml_or sample backend sample
  assert_output 'sample'
  run dytoy::get_yaml_or sample github.host ""
  assert_success
  assert_output ''
}

@test "dytoy::run_script shows the script content in dry-run mode" {
  export DRY_RUN='true'
  local script_path="${BATS_TEST_TMPDIR}/sample.sh"
  printf 'echo hello from sample\n' > "${script_path}"

  run dytoy::run_script "${script_path}"
  assert_success
  assert_output --partial "RUN: ${script_path}"
  assert_output --partial 'echo hello from sample'
}

@test "dytoy::run_script reports nothing for a script without content" {
  export DRY_RUN='true'
  local script_path="${BATS_TEST_TMPDIR}/empty.sh"
  : > "${script_path}"

  run dytoy::run_script "${script_path}"
  assert_success
  refute_output --partial "RUN:"
}

@test "dytoy::is_installed_command respects a custom install location" {
  mkdir -p "${BATS_TEST_TMPDIR}/custom-bin"
  touch "${BATS_TEST_TMPDIR}/custom-bin/sample"
  export ONLY_NOT_INSTALLED='true'

  run dytoy::is_installed_command sample "${BATS_TEST_TMPDIR}/custom-bin"
  assert_success
}

@test "dytoy::iterate processes only tools for the active method" {
  write_tools_yaml << 'EOF'
- name: first
  method: binary
- name: second
  method: binary
- name: third
  method: shell
EOF
  METHOD='binary'
  TOOL='@empty'
  local output_file="${BATS_TEST_TMPDIR}/tools"
  function collect_tool {
    printf '%s
' "$1" >> "${output_file}"
  }

  run dytoy::iterate collect_tool
  assert_success
  run cat "${output_file}"
  assert_success
  assert_output $'first
second'
}

@test "dytoy::iterate resumes after the last tool that succeeded" {
  write_tools_yaml << 'EOF'
- name: first
  method: binary
- name: second
  method: binary
EOF
  METHOD='binary'
  TOOL='@empty'
  local output_file="${BATS_TEST_TMPDIR}/tools"
  # shellcheck disable=SC2329 # invoked by dytoy::iterate
  function install_tool {
    printf '%s\n' "$1" >> "${output_file}"
    # An installer stops the whole run, as dybatpho::die does
    [[ "$1" != "second" || -f "${BATS_TEST_TMPDIR}/fixed" ]] || exit 1
  }

  run dytoy::iterate install_tool
  assert_failure
  touch "${BATS_TEST_TMPDIR}/fixed"
  run dytoy::iterate install_tool
  assert_success
  run cat "${output_file}"
  assert_output $'first\nsecond\nsecond'
}

@test "dytoy::iterate installs again an edited tool or with --no-check-installed" {
  write_tools_yaml << 'EOF'
- name: first
  method: binary
EOF
  METHOD='binary'
  TOOL='@empty'
  local output_file="${BATS_TEST_TMPDIR}/tools"
  # shellcheck disable=SC2329 # invoked by dytoy::iterate
  function install_tool { printf '%s\n' "$1" >> "${output_file}"; }

  run dytoy::iterate install_tool
  run dytoy::iterate install_tool
  ONLY_NOT_INSTALLED='false' run dytoy::iterate install_tool
  write_tools_yaml << 'EOF'
- name: first
  method: binary
  version: v1
EOF
  run dytoy::iterate install_tool
  run cat "${output_file}"
  assert_output $'first\nfirst\nfirst'
}

@test "dytoy::install_dependencies dispatches through the dytoy subcommand of its method" {
  export DRY_RUN='true'
  write_tools_yaml << 'EOF'
- name: sample
  method: binary
  dependencies:
    - helper
- name: helper
  method: shell
EOF

  run dytoy::install_dependencies sample
  assert_success
  assert_output --partial "${HOME}/.local/bin/dytoy shell -i -t helper"
}

@test "dytoy::is_defined fails for a missing tool" {
  write_tools_yaml << 'EOF'
- name: sample
  method: binary
EOF

  run --separate-stderr dytoy::is_defined missing_tool binary
  assert_failure
  assert_stderr --partial "Not found missing_tool tool"
}

@test "dytoy::is_defined fails for disabled tool" {
  write_tools_yaml << 'EOF'
- name: sample
  method: os
  enabled: false
EOF

  run --separate-stderr dytoy::is_defined sample os
  assert_failure
  assert_stderr --partial "Tool sample is disabled"
}

@test "dytoy::is_defined succeeds for a defined, enabled tool" {
  write_tools_yaml << 'EOF'
- name: sample
  method: os
EOF

  run dytoy::is_defined sample os
  assert_success
}

@test "dytoy::is_invalid_essential respects ONLY_ESSENTIAL" {
  export ONLY_ESSENTIAL='true'
  write_tools_yaml << 'EOF'
- name: sample
  method: binary
  is_essential: false
EOF

  run dytoy::is_invalid_essential sample
  assert_success
}

@test "dytoy::is_installed_package delegates to the package-specific checker" {
  export ONLY_NOT_INSTALLED='true'
  function package_manager::check_installed_apt {
    [[ "$1" == "sample" ]]
  }

  run dytoy::is_installed_package sample apt
  assert_success
}

@test "dytoy::enable_service enables nothing without an init system" {
  function init_system::enable_openrc_service { printf 'called\n'; }
  run dytoy::enable_service '{"service": "sshd", "is_user_service": false}' none
  assert_success
  refute_output --partial 'called'
  DYTOY_INIT_SYSTEM=none run dytoy::enable_service '{"service": "sshd", "is_user_service": false}' openrc
  assert_success
  refute_output --partial 'called'
}

@test "dytoy::enable_service dispatches to the requested init backend" {
  local args_file="${BATS_TEST_TMPDIR}/service-args"
  function init_system::enable_systemd_service {
    printf '%s|%s\n' "$1" "$2" > "${args_file}"
  }

  run dytoy::enable_service '{"service": "sshd", "is_user_service": true}' systemd
  assert_success
  run cat "${args_file}"
  assert_success
  assert_output "sshd|true"
}

@test "dytoy::install_ubuntu_package adds repos installs packages and enables services" {
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function dytoy::add_apt_repo { printf 'repo:%s\n' "$2" >> "${actions_file}"; }
  function dytoy::is_installed_package { return 1; }
  function package_manager::install_via_apt { printf 'install:%s\n' "$1" >> "${actions_file}"; }
  function dytoy::enable_service { printf 'service:%s\n' "$2" >> "${actions_file}"; }

  run dytoy::install_ubuntu_package '{"name": "ripgrep", "service": "sshd"}'
  assert_success
  run cat "${actions_file}"
  assert_success
  assert_output $'repo:ubuntu\ninstall:ripgrep\nservice:systemd'
}

@test "dytoy::install_macos_package passes the brew flags of the tool type" {
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function dytoy::is_installed_package { return 1; }
  function dytoy::enable_service { true; }
  function package_manager::install_via_brew { printf 'brew:%s\n' "$*" >> "${actions_file}"; }

  run dytoy::install_macos_package '{"name":"firefox","type":"cask","version":"HEAD","repo":"null"}'
  assert_success
  run dytoy::install_macos_package '{"name":"fzf","type":"formula","version":"latest","repo":"null"}'
  assert_success
  run dytoy::install_macos_package '{"name":"neovim","repo":"null"}'
  assert_success
  run cat "${actions_file}"
  assert_output $'brew:firefox --cask --force --HEAD\nbrew:fzf --formula\nbrew:neovim --formula'
}

@test "dytoy::install_macos_package installs a pinned version as its versioned package" {
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function dytoy::is_installed_package {
    printf 'check:%s\n' "$1" >> "${actions_file}"
    return 1
  }
  function dytoy::enable_service { true; }
  function package_manager::install_via_brew { printf 'brew:%s\n' "$*" >> "${actions_file}"; }

  run dytoy::install_macos_package '{"name":"python","version":"3.12","repo":"null"}'
  assert_success
  run cat "${actions_file}"
  assert_output $'check:python@3.12\nbrew:python@3.12 --formula'
}

@test "dytoy::install_macos_package appends the params of the tool" {
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function dytoy::is_installed_package { return 1; }
  function dytoy::enable_service { true; }
  function package_manager::install_via_brew { printf 'brew:%s\n' "$*" >> "${actions_file}"; }

  run dytoy::install_macos_package \
    '{"name":"font-roboto","type":"cask","repo":"null","params":["--no-quarantine","--require-sha"]}'
  assert_success
  run cat "${actions_file}"
  assert_output 'brew:font-roboto --cask --force --no-quarantine --require-sha'
}

@test "dytoy::install_* hand the params of the tool to every package manager" {
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function dytoy::is_installed_package { return 1; }
  function dytoy::enable_service { true; }
  function dytoy::add_apt_repo { true; }
  local via
  for via in portage pacman apt apk termux fdroidcl flatpak mas; do
    eval "function package_manager::install_via_${via} { printf '${via}:%s\\n' \"\$*\" >> \"\${actions_file}\"; }"
  done
  local yaml='{"name":"tool","repo":"null","url":"null","params":["--one","--two"]}'

  run dytoy::install_gentoo_package "${yaml}" openrc
  assert_success
  run dytoy::install_arch_package "${yaml}"
  assert_success
  run dytoy::install_ubuntu_package "${yaml}"
  assert_success
  run dytoy::install_alpine_package "${yaml}"
  assert_success
  run dytoy::install_termux_package "${yaml}"
  assert_success
  run dytoy::install_fdroid_package "${yaml}"
  assert_success
  run dytoy::install_flatpak_package '{"name":"tool","repo":"flathub","url":"null","params":["--one","--two"]}'
  assert_success
  run dytoy::install_macos_package '{"name":"tool","type":"store","params":["--one","--two"]}'
  assert_success
  run cat "${actions_file}"
  assert_output "$(printf '%s\n' \
    'portage:tool --one --two' 'pacman:tool --one --two' 'apt:tool --one --two' \
    'apk:tool --one --two' 'termux:tool --one --two' 'fdroidcl:tool --one --two' \
    'flatpak:tool flathub --one --two' 'mas:tool --one --two')"
}

@test "dytoy::get_package_spec maps a version onto each OS package manager" {
  run dytoy::get_package_spec portage app-editors/neovim null
  assert_output 'app-editors/neovim'
  run dytoy::get_package_spec apt ripgrep latest
  assert_output 'ripgrep'
  run dytoy::get_package_spec portage app-editors/neovim HEAD
  assert_output '=app-editors/neovim-9999'
  run dytoy::get_package_spec portage app-editors/neovim 0.11.4
  assert_output '=app-editors/neovim-0.11.4'
  run dytoy::get_package_spec pacman neovim HEAD
  assert_output 'neovim-git'
  run dytoy::get_package_spec apt ripgrep 14.1.0-1
  assert_output 'ripgrep=14.1.0-1'
  run dytoy::get_package_spec termux neovim 0.11.4
  assert_output 'neovim=0.11.4'
  run dytoy::get_package_spec apk neovim 0.11.4-r0
  assert_output 'neovim=0.11.4-r0'
}

@test "dytoy::get_package_spec rejects a version the package manager can't install" {
  run dytoy::get_package_spec pacman neovim 0.11.4
  assert_failure
  assert_output --partial "pacman can't install version 0.11.4 of neovim"
  run dytoy::get_package_spec apt neovim HEAD
  assert_failure
  assert_output --partial "apt can't install the HEAD of neovim"
  run dytoy::get_package_spec flatpak org.example.App 1.0
  assert_failure
}

@test "dytoy::install_* install the version of an OS package" {
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function dytoy::is_installed_package {
    printf 'check:%s\n' "$1" >> "${actions_file}"
    return 1
  }
  function dytoy::enable_service { true; }
  function dytoy::add_apt_repo { true; }
  local via
  for via in portage pacman apt apk termux; do
    eval "function package_manager::install_via_${via} { printf '${via}:%s\\n' \"\$*\" >> \"\${actions_file}\"; }"
  done

  run dytoy::install_gentoo_package '{"name":"app-editors/neovim","repo":"null","version":"HEAD"}' openrc
  assert_success
  run dytoy::install_arch_package '{"name":"neovim","version":"HEAD"}'
  assert_success
  run dytoy::install_ubuntu_package '{"name":"ripgrep","version":"14.1.0-1"}'
  assert_success
  run dytoy::install_alpine_package '{"name":"neovim","version":"0.11.4-r0"}'
  assert_success
  run dytoy::install_termux_package '{"name":"neovim","version":"0.11.4"}'
  assert_success
  run cat "${actions_file}"
  assert_output "$(printf '%s\n' \
    'check:app-editors/neovim' 'portage:=app-editors/neovim-9999' \
    'check:neovim-git' 'pacman:neovim-git' \
    'check:ripgrep' 'apt:ripgrep=14.1.0-1' \
    'check:neovim' 'apk:neovim=0.11.4-r0' \
    'check:neovim' 'termux:neovim=0.11.4')"
}

@test "dytoy::install_arch_package stops on a version paru can't install" {
  function dytoy::install_package { printf 'installed\n'; }
  run dytoy::install_arch_package '{"name":"neovim","version":"0.11.4"}'
  assert_failure
  refute_output --partial 'installed'
}

@test "dytoy::install_* pass no params when the tool has none" {
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function dytoy::is_installed_package { return 1; }
  function dytoy::enable_service { true; }
  function package_manager::install_via_pacman { printf 'pacman:%s|\n' "$*" >> "${actions_file}"; }

  run dytoy::install_arch_package '{"name":"tool"}'
  assert_success
  run cat "${actions_file}"
  assert_output 'pacman:tool|'
}

@test "dytoy::install_macos_rosetta installs rosetta when runtime is missing" {
  function dybatpho::is {
    if [[ "$1" == "file" && "$2" == "/usr/libexec/rosetta/runtime" ]]; then
      return 1
    fi
    command dybatpho::is "$@"
  }
  cat > "${HOME}/.local/bin/softwareupdate" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$HOME/softwareupdate.args"
EOF
  chmod +x "${HOME}/.local/bin/softwareupdate"

  run dytoy::install_macos_rosetta
  assert_success
  run cat "${HOME}/softwareupdate.args"
  assert_success
  assert_output "--install-rosetta --agree-to-license"
}

@test "dytoy::install_macos_rosetta succeeds when rosetta is already there" {
  function dybatpho::is {
    if [[ "$1" == "file" && "$2" == "/usr/libexec/rosetta/runtime" ]]; then
      return 0
    fi
    command dybatpho::is "$@"
  }

  run dytoy::install_macos_rosetta
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# dytoy::install_*  – package dispatch helpers
# ---------------------------------------------------------------------------

@test "dytoy::install_gentoo_package calls install_via_portage for new packages" {
  local yaml='{"name":"app-misc/htop","repo":"null","url":"null"}'
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function dytoy::is_installed_package { return 1; }
  function package_manager::install_via_portage { printf 'portage:%s\n' "$1" >> "${actions_file}"; }
  function dytoy::enable_service { true; }
  run dytoy::install_gentoo_package "$yaml" "openrc"
  assert_success
  run cat "${actions_file}"
  assert_output "portage:app-misc/htop"
}

@test "dytoy::install_gentoo_package skips already-installed packages" {
  local yaml='{"name":"app-misc/htop","repo":"null","url":"null"}'
  function dytoy::is_installed_package { return 0; }
  function package_manager::install_via_portage { return 1; }
  run dytoy::install_gentoo_package "$yaml" "openrc"
  assert_success
}

@test "dytoy::install_arch_package calls install_via_pacman for new packages" {
  local yaml='{"name":"htop","repo":"null"}'
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function dytoy::is_installed_package { return 1; }
  function package_manager::install_via_pacman { printf 'pacman:%s\n' "$1" >> "${actions_file}"; }
  function dytoy::enable_service { true; }
  run dytoy::install_arch_package "$yaml"
  assert_success
  run cat "${actions_file}"
  assert_output "pacman:htop"
}

@test "dytoy::install_arch_package skips already-installed packages" {
  local yaml='{"name":"htop","repo":"null"}'
  function dytoy::is_installed_package { return 0; }
  function package_manager::install_via_pacman { return 1; }
  run dytoy::install_arch_package "$yaml"
  assert_success
}

@test "dytoy::install_alpine_package calls install_via_apk for new packages" {
  local yaml='{"name":"curl","repo":"null"}'
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function dytoy::is_installed_package { return 1; }
  function package_manager::install_via_apk { printf 'apk:%s\n' "$1" >> "${actions_file}"; }
  function dytoy::enable_service { true; }
  run dytoy::install_alpine_package "$yaml"
  assert_success
  run cat "${actions_file}"
  assert_output "apk:curl"
}

@test "dytoy::install_termux_package calls install_via_termux for new packages" {
  local yaml='{"name":"git","repo":"null"}'
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function dytoy::is_installed_package { return 1; }
  function package_manager::install_via_termux { printf 'termux:%s\n' "$1" >> "${actions_file}"; }
  function dytoy::enable_service { true; }
  run dytoy::install_termux_package "$yaml"
  assert_success
  run cat "${actions_file}"
  assert_output "termux:git"
}

@test "dytoy::install_fdroid_package calls install_via_fdroidcl for new packages" {
  local yaml='{"name":"com.termux","repo":"null","url":"null"}'
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function dytoy::is_installed_package { return 1; }
  function package_manager::install_via_fdroidcl { printf 'fdroid:%s\n' "$1" >> "${actions_file}"; }
  run dytoy::install_fdroid_package "$yaml"
  assert_success
  run cat "${actions_file}"
  assert_output "fdroid:com.termux"
}

@test "dytoy::install_fdroid_package adds fdroid repo when repo is specified" {
  local yaml='{"name":"com.example.App","repo":"myrepo","url":"https://example.com/fdroid/repo"}'
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function package_manager::add_fdroid_repo { printf 'add_repo:%s\n' "$1" >> "${actions_file}"; }
  function dytoy::is_installed_package { return 1; }
  function package_manager::install_via_fdroidcl { printf 'fdroid:%s\n' "$1" >> "${actions_file}"; }
  run dytoy::install_fdroid_package "$yaml"
  assert_success
  run cat "${actions_file}"
  assert_line "add_repo:myrepo"
  assert_line "fdroid:com.example.App"
}

@test "__dytoy_install_store_section installs the store, then its packages inside the section hook" {
  write_tools_yaml << 'EOF'
- name: app
  method: os
  fdroid:
    packages:
      - name: org.app
- name: bare
  method: os
EOF
  # shellcheck disable=SC2329 # stand-ins called by the section installer
  function misc::install_tool { printf 'store:%s\n' "$1"; }
  # shellcheck disable=SC2329
  function package_manager::init_fdroid { printf 'init\n'; }
  # shellcheck disable=SC2329
  function dytoy::run_section_hook { printf 'hook:%s:%s\n' "$2" "$3"; }
  # shellcheck disable=SC2329
  function dytoy::install_fdroid_package {
    local name
    name="$(dybatpho::json_get "$1" .name)"
    printf 'install:%s\n' "${name}"
  }

  run __dytoy_install_store_section app fdroid fdroidcl
  assert_success
  assert_output $'store:fdroidcl\ninit\nhook:before:fdroid\ninstall:org.app\nhook:after:fdroid'

  run __dytoy_install_store_section bare fdroid fdroidcl
  assert_success
  assert_output ''
}

@test "dytoy::install_flatpak_package calls install_via_flatpak for new packages" {
  local yaml='{"name":"org.gnome.Calendar","repo":"flathub","url":"null"}'
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function dytoy::is_installed_package { return 1; }
  function package_manager::install_via_flatpak { printf 'flatpak:%s|%s\n' "$1" "$2" >> "${actions_file}"; }
  run dytoy::install_flatpak_package "$yaml"
  assert_success
  run cat "${actions_file}"
  assert_output "flatpak:org.gnome.Calendar|flathub"
}

@test "dytoy::add_apt_repo calls package_manager::add_apt_repo with expanded suite for ubuntu" {
  local yaml='{"name":"sample","repo":"https://packages.example/dists/%v","suite":"null","components":"main","key":"ABCD1234","repo_name":"null"}'
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function package_manager::add_apt_repo { printf 'add_apt_repo:%s|%s\n' "$1" "$3" >> "${actions_file}"; }
  function package_manager::sync_apt_repo { true; }
  # dybatpho::os_release reads this file instead of /etc/os-release
  export DYBATPHO_OS_RELEASE="${BATS_TEST_TMPDIR}/os-release"
  printf 'ID=ubuntu\nVERSION_ID="22.04"\nUBUNTU_CODENAME=jammy\n' > "${DYBATPHO_OS_RELEASE}"
  run dytoy::add_apt_repo "$yaml" "ubuntu"
  assert_success
  run cat "${actions_file}"
  assert_output "add_apt_repo:sample|jammy"
}

@test "dytoy::add_apt_repo returns early when repo is null" {
  local yaml='{"name":"sample","repo":"null","suite":"null","components":"main","key":"ABCD1234","repo_name":"null"}'
  local called_file="${BATS_TEST_TMPDIR}/called"
  function package_manager::add_apt_repo { printf 'called\n' > "${called_file}"; }
  run dytoy::add_apt_repo "$yaml" "ubuntu"
  assert_success
  refute [ -f "${called_file}" ]
}

@test "dytoy::is_package_for_release matches the release against semver ranges" {
  export DYTOY_RELEASE='24.04'
  dytoy::is_package_for_release '{"name":"neovim","releases":["24.04"]}'
  dytoy::is_package_for_release '{"name":"neovim","releases":[">=24.04"]}'
  dytoy::is_package_for_release '{"name":"neovim","releases":[">22.04 <24.10"]}'
  dytoy::is_package_for_release '{"name":"neovim","releases":["22.04 || 24.04"]}'
  run dytoy::is_package_for_release '{"name":"neovim","releases":[">=22.04 <24.04"]}'
  assert_failure
  run dytoy::is_package_for_release '{"name":"neovim","releases":["24.10"]}'
  assert_failure
}

@test "dytoy::is_package_for_release matches a partial range against a full release" {
  export DYTOY_RELEASE='3.20.3'
  dytoy::is_package_for_release '{"name":"neovim","releases":["3.20"]}'
  dytoy::is_package_for_release '{"name":"neovim","releases":["3"]}'
  run dytoy::is_package_for_release '{"name":"neovim","releases":["3.21"]}'
  assert_failure
}

@test "dytoy::is_package_for_release skips a package with releases on a rolling release" {
  export DYTOY_RELEASE='rolling'
  run dytoy::is_package_for_release '{"name":"neovim","releases":[">=1"]}'
  assert_failure
}

@test "dytoy::is_package_for_release keeps a package without releases" {
  export DYTOY_RELEASE='22.04'
  dytoy::is_package_for_release '{"name":"ripgrep"}'
}

@test "dytoy::is_package_for_release keeps a package when any of its releases matches" {
  export DYTOY_RELEASE='24.04'
  dytoy::is_package_for_release '{"name":"neovim","releases":["<22.04",">=24.04"]}'
  run dytoy::is_package_for_release '{"name":"neovim","releases":["<24.04"]}'
  assert_failure
}

@test "dytoy::is_package_for_release reads the release from os-release" {
  unset DYTOY_RELEASE
  # dybatpho::distro_version asks sw_vers on macOS, so pretend to be Linux.
  function dybatpho::platform { printf 'linux\n'; }
  export DYBATPHO_OS_RELEASE="${BATS_TEST_TMPDIR}/os-release"
  printf 'ID=ubuntu\nVERSION_ID="22.04"\n' > "${DYBATPHO_OS_RELEASE}"
  dytoy::is_package_for_release '{"name":"neovim","releases":["<24.04"]}'
  run dytoy::is_package_for_release '{"name":"neovim","releases":[">=24.04"]}'
  assert_failure
}

@test "dytoy::is_package_for_release skips a package with releases on an OS without one" {
  unset DYTOY_RELEASE
  function dybatpho::distro_version { return 1; }
  run dytoy::is_package_for_release '{"name":"neovim","releases":[">=24.04"]}'
  assert_failure
}

@test "__dytoy_lines_into splits output into lines and keeps the exit code" {
  local -a lines=(stale)
  __dytoy_lines_into lines printf 'one\ntwo words\n'
  assert_equal "${#lines[@]}" 2
  assert_equal "${lines[1]}" 'two words'

  __dytoy_lines_into lines printf ''
  assert_equal "${#lines[@]}" 0

  run __dytoy_lines_into lines false
  assert_failure

  # What a failing command printed is kept.
  __dytoy_lines_into lines sh -c 'printf "partial\n"; exit 3' || assert_equal "$?" 3
  assert_equal "${lines[*]}" 'partial'
}

@test "dytoy::iterate converts the YAML file once for the whole run" {
  write_tools_yaml << 'EOF'
- name: first
  method: binary
  version: v1
- name: second
  method: binary
EOF
  local METHOD='binary' ONLY_ESSENTIAL='false' ONLY_NOT_INSTALLED='false' TOOL='@empty'
  local count_file="${BATS_TEST_TMPDIR}/conversions" bin="${BATS_TEST_TMPDIR}/bin" real_yq
  real_yq="$(command -v yq)"
  mkdir -p "${bin}"
  # A yq that counts how often the file is converted, leaving out the version
  # check dybatpho makes first.
  # dyshellint disable=SC2016 "$1" and "$@" belong to the generated script
  printf '#!/usr/bin/env bash\n[[ "$1" == --version ]] || printf x >> %q\nexec %q "$@"\n' \
    "${count_file}" "${real_yq}" > "${bin}/yq"
  chmod +x "${bin}/yq"
  local PATH="${bin}:${PATH}"
  # shellcheck disable=SC2329 # invoked by dytoy::iterate
  function _install { dytoy::get_version "$1"; }

  run dytoy::iterate _install
  assert_success
  assert_output --partial 'v1'
  run cat "${count_file}"
  assert_output 'x'
}

@test "dytoy::iterate leaves out a non-essential tool and refuses an unknown one" {
  write_tools_yaml << 'EOF'
- name: core
  method: binary
  is_essential: true
- name: extra
  method: binary
EOF
  local METHOD='binary' ONLY_ESSENTIAL='true' ONLY_NOT_INSTALLED='false' TOOL='@empty'
  # shellcheck disable=SC2329 # invoked by dytoy::iterate
  function _install { printf 'install:%s\n' "$1"; }
  run dytoy::iterate _install
  assert_success
  assert_output --partial 'install:core'
  refute_output --partial 'install:extra'

  TOOL='ghost'
  run --separate-stderr dytoy::iterate _install
  assert_failure
  assert_stderr --partial 'Not found ghost tool'
}

@test "dytoy::iterate installs nothing when tools.yaml is missing" {
  export TOOL='@empty' METHOD='os'
  # shellcheck disable=SC2329 # invoked by dytoy::iterate
  function _install { printf 'install:%s\n' "$1"; }
  run dytoy::iterate _install
  assert_success
  refute_output --partial 'install:'
  assert_output --partial 'Installed all os tools'
}
