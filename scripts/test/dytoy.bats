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
  github:
    repo: owner/repo
EOF

  run dytoy::get_yaml sample method
  assert_success
  assert_output 'binary'

  run dytoy::get_yaml sample dependencies
  assert_success
  assert_output 'helper'
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

@test "dytoy::enable_service dispatches to the requested init backend" {
  local args_file="${BATS_TEST_TMPDIR}/service-args"
  function init_system::enable_systemd_service {
    printf '%s|%s\n' "$1" "$2" > "${args_file}"
  }

  run dytoy::enable_service $'service: sshd\nis_user_service: true' systemd
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

  run dytoy::install_ubuntu_package $'name: ripgrep\nservice: sshd'
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
  function dytoy::is_installed_package { printf 'check:%s\n' "$1" >> "${actions_file}"; return 1; }
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
  function dytoy::is_installed_package { printf 'check:%s\n' "$1" >> "${actions_file}"; return 1; }
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
  # Stub /etc/os-release
  function grep {
    if [[ "$*" == *UBUNTU_CODENAME* ]]; then
      printf 'UBUNTU_CODENAME=jammy\n'
    else command grep "$@"; fi
  }
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
