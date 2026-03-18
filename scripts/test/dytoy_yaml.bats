setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/dytoy_yaml.sh"
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

@test "dytoy::install_dependencies dispatches through the tool-specific dytoy entrypoint" {
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
  assert_output --partial "${HOME}/.local/bin/dytoy_shell -i -t helper"
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
  function pkg::check_installed_apt {
    [ "$1" = "sample" ]
  }

  run dytoy::is_installed_package sample apt
  assert_success
}

@test "dytoy::enable_service dispatches to the requested init backend" {
  local args_file="${BATS_TEST_TMPDIR}/service-args"
  function init::enable_systemd_service {
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
  function pkg::install_via_apt { printf 'install:%s\n' "$1" >> "${actions_file}"; }
  function dytoy::enable_service { printf 'service:%s\n' "$2" >> "${actions_file}"; }

  run dytoy::install_ubuntu_package $'name: ripgrep\nservice: sshd'
  assert_success
  run cat "${actions_file}"
  assert_success
  assert_output $'repo:ubuntu\ninstall:ripgrep\nservice:systemd'
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

# ---------------------------------------------------------------------------
# dytoy::install_*  – package dispatch helpers
# ---------------------------------------------------------------------------

@test "dytoy::install_gentoo_package calls install_via_portage for new packages" {
  local yaml='{"name":"app-misc/htop","repo":"null","url":"null"}'
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function dytoy::is_installed_package { return 1; }
  function pkg::install_via_portage { printf 'portage:%s\n' "$1" >> "${actions_file}"; }
  function dytoy::enable_service { true; }
  run dytoy::install_gentoo_package "$yaml" "openrc"
  assert_success
  run cat "${actions_file}"
  assert_output "portage:app-misc/htop"
}

@test "dytoy::install_gentoo_package skips already-installed packages" {
  local yaml='{"name":"app-misc/htop","repo":"null","url":"null"}'
  function dytoy::is_installed_package { return 0; }
  function pkg::install_via_portage { return 1; }
  run dytoy::install_gentoo_package "$yaml" "openrc"
  assert_success
}

@test "dytoy::install_arch_package calls install_via_pacman for new packages" {
  local yaml='{"name":"htop","repo":"null"}'
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function dytoy::is_installed_package { return 1; }
  function pkg::install_via_pacman { printf 'pacman:%s\n' "$1" >> "${actions_file}"; }
  function dytoy::enable_service { true; }
  run dytoy::install_arch_package "$yaml"
  assert_success
  run cat "${actions_file}"
  assert_output "pacman:htop"
}

@test "dytoy::install_arch_package skips already-installed packages" {
  local yaml='{"name":"htop","repo":"null"}'
  function dytoy::is_installed_package { return 0; }
  function pkg::install_via_pacman { return 1; }
  run dytoy::install_arch_package "$yaml"
  assert_success
}

@test "dytoy::install_alpine_package calls install_via_apk for new packages" {
  local yaml='{"name":"curl","repo":"null"}'
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function dytoy::is_installed_package { return 1; }
  function pkg::install_via_apk { printf 'apk:%s\n' "$1" >> "${actions_file}"; }
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
  function pkg::install_via_termux { printf 'termux:%s\n' "$1" >> "${actions_file}"; }
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
  function pkg::install_via_fdroidcl { printf 'fdroid:%s\n' "$1" >> "${actions_file}"; }
  run dytoy::install_fdroid_package "$yaml"
  assert_success
  run cat "${actions_file}"
  assert_output "fdroid:com.termux"
}

@test "dytoy::install_fdroid_package adds fdroid repo when repo is specified" {
  local yaml='{"name":"com.example.App","repo":"myrepo","url":"https://example.com/fdroid/repo"}'
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function pkg::add_fdroid_repo { printf 'add_repo:%s\n' "$1" >> "${actions_file}"; }
  function dytoy::is_installed_package { return 1; }
  function pkg::install_via_fdroidcl { printf 'fdroid:%s\n' "$1" >> "${actions_file}"; }
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
  function pkg::install_via_flatpak { printf 'flatpak:%s|%s\n' "$1" "$2" >> "${actions_file}"; }
  run dytoy::install_flatpak_package "$yaml"
  assert_success
  run cat "${actions_file}"
  assert_output "flatpak:org.gnome.Calendar|flathub"
}

@test "dytoy::add_apt_repo calls pkg::add_apt_repo with expanded suite for ubuntu" {
  local yaml='{"name":"sample","repo":"https://packages.example/dists/%v","suite":"null","components":"main","key":"ABCD1234","repo_name":"null"}'
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function pkg::add_apt_repo { printf 'add_apt_repo:%s|%s\n' "$1" "$3" >> "${actions_file}"; }
  function pkg::sync_apt_repo { true; }
  # Stub /etc/os-release
  function grep {
    if [[ "$*" == *UBUNTU_CODENAME* ]]; then printf 'UBUNTU_CODENAME=jammy\n'
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
  function pkg::add_apt_repo { printf 'called\n' > "${called_file}"; }
  run dytoy::add_apt_repo "$yaml" "ubuntu"
  assert_success
  refute [ -f "${called_file}" ]
}
