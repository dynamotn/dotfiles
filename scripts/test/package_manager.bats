setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/package_manager.sh"
  eval "$(declare -f dybatpho::is | sed '1s/dybatpho::is/__orig_dybatpho_is/')"
}

@test "package_manager::add_apt_repo converts fingerprints to keyserver URLs in dry-run mode" {
  export DRY_RUN='true'
  # A rehearsal prints only the host of a URL, so the key's URL is read from
  # the download call itself.
  local url_file="${BATS_TEST_TMPDIR}/key-url"
  # shellcheck disable=SC2329 # invoked by package_manager::add_apt_repo
  function dybatpho::curl_download {
    printf '%s\n' "$1" > "${url_file}"
  }

  run package_manager::add_apt_repo sample https://packages.example stable main ABCD1234
  assert_success
  assert_output --partial '/etc/apt/trusted.gpg.d/sample.gpg'
  assert_output --partial '/etc/apt/sources.list.d/sample.list'
  run cat "${url_file}"
  assert_output 'https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0xABCD1234'
}

@test "package_manager::add_apt_repo finds Termux's prefix when PREFIX is not set" {
  # Termux exports PREFIX, but a shell that has the Termux tools without it --
  # a proot, or a stripped environment -- stopped on `PREFIX: unbound variable`.
  export DRY_RUN='true'
  printf '#!/bin/sh\n' > "${HOME}/.local/bin/termux-setup-storage"
  chmod +x "${HOME}/.local/bin/termux-setup-storage"
  unset PREFIX

  run --separate-stderr package_manager::add_apt_repo sample https://packages.example stable main ABCD1234
  assert_success
  refute_stderr --partial "unbound variable"
  assert_output --partial '/data/data/com.termux/files/usr/etc/apt/sources.list.d/sample.list'
}

@test "package_manager::check_installed_fdroidcl and check_installed_mas read an id that starts with a dash" {
  # The id went to grep as its first operand, so one starting with `-` was read
  # as an option and an installed application was reported missing.
  printf '#!/bin/sh\nprintf "package:-42\\npackage:org.example\\n"\n' > "${HOME}/.local/bin/cmd"
  printf '#!/bin/sh\nprintf -- "-42 Odd App\\n497799835 Xcode\\n"\n' > "${HOME}/.local/bin/mas"
  chmod +x "${HOME}/.local/bin/cmd" "${HOME}/.local/bin/mas"

  run package_manager::check_installed_fdroidcl -42
  assert_success
  run package_manager::check_installed_mas -42
  assert_success
  run package_manager::check_installed_mas 1234
  assert_failure
}

@test "package_manager::add_flatpak_repo adds a missing remote in dry-run mode" {
  export DRY_RUN='true'
  stub flatpak ': if [ "$1" = "remote-list" ]; then exit 0; fi'

  run package_manager::add_flatpak_repo flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  assert_success
  assert_output --partial 'flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo'
  unstub flatpak
}

@test "package_manager::check_installed_apt delegates to dpkg-query" {
  cat > "${HOME}/.local/bin/dpkg-query" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-W" && "$4" == "sample" ]]; then
  printf 'install ok installed'
  exit 0
fi
exit 1
EOF
  chmod +x "${HOME}/.local/bin/dpkg-query"

  run package_manager::check_installed_apt sample
  assert_success
}

@test "package_manager::install_via_flatpak prints the install command in dry-run mode" {
  export DRY_RUN='true'

  run package_manager::install_via_flatpak com.example.App flathub
  assert_success
  assert_output --partial 'flatpak install -y --user flathub com.example.App'
}

@test "package_manager::init_flatpak wires repository setup and Flatseal install" {
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function package_manager::add_flatpak_repo { printf 'repo:%s|%s\n' "$1" "$2" >> "${actions_file}"; }
  function package_manager::install_via_flatpak { printf 'install:%s|%s\n' "$1" "$2" >> "${actions_file}"; }

  run package_manager::init_flatpak
  assert_success
  run cat "${actions_file}"
  assert_success
  assert_output $'repo:flathub|https://dl.flathub.org/repo/flathub.flatpakrepo\ninstall:com.github.tchx84.Flatseal|flathub'
}

# ---------------------------------------------------------------------------
# package_manager::sync_* — each prints a progress message and runs the sync command
# ---------------------------------------------------------------------------

@test "package_manager::sync_portage_repo prints progress and syncs portage in dry-run mode" {
  export DRY_RUN='true'
  run package_manager::sync_portage_repo
  assert_success
  assert_output --partial 'emerge --sync'
}

@test "package_manager::sync_pacman_repo uses paru when available" {
  export DRY_RUN='true'
  cat > "${HOME}/.local/bin/paru" << 'EOF'
#!/usr/bin/env bash
echo "paru $*"
EOF
  chmod +x "${HOME}/.local/bin/paru"
  run package_manager::sync_pacman_repo
  assert_success
  assert_output --partial 'paru -Sy'
}

@test "package_manager::sync_pacman_repo falls back to pacman when paru is missing" {
  export DRY_RUN='true'
  function dybatpho::is {
    if [[ "$1" == "command" && "$2" == "paru" ]]; then
      return 1
    fi
    __orig_dybatpho_is "$@"
  }
  run package_manager::sync_pacman_repo
  assert_success
  assert_output --partial 'pacman -Sy'
}

@test "package_manager::sync_apt_repo calls apt update in dry-run mode" {
  export DRY_RUN='true'
  run package_manager::sync_apt_repo
  assert_success
  assert_output --partial 'apt-get update'
}

@test "package_manager::sync_apk_repo calls apk update in dry-run mode" {
  export DRY_RUN='true'
  run package_manager::sync_apk_repo
  assert_success
  assert_output --partial 'apk update'
}

@test "package_manager::sync_termux_repo calls pkg update in dry-run mode" {
  export DRY_RUN='true'
  run package_manager::sync_termux_repo
  assert_success
  assert_output --partial 'pkg update'
}

@test "package_manager::sync_fdroid_repo calls fdroidcl update in dry-run mode" {
  export DRY_RUN='true'
  run package_manager::sync_fdroid_repo
  assert_success
  assert_output --partial 'fdroidcl update'
}

@test "package_manager::sync_brew_repo calls brew update in dry-run mode" {
  export DRY_RUN='true'
  run package_manager::sync_brew_repo
  assert_success
  assert_output --partial 'brew update'
}

# ---------------------------------------------------------------------------
# package_manager::init_* — delegate to sync + optional install
# ---------------------------------------------------------------------------

@test "package_manager::init_ubuntu delegates to package_manager::sync_apt_repo" {
  local called_file="${BATS_TEST_TMPDIR}/called"
  function package_manager::sync_apt_repo { printf 'synced\n' > "${called_file}"; }
  run package_manager::init_ubuntu
  assert_success
  run cat "${called_file}"
  assert_output "synced"
}

@test "package_manager::init_alpine delegates to package_manager::sync_apk_repo" {
  local called_file="${BATS_TEST_TMPDIR}/called"
  function package_manager::sync_apk_repo { printf 'synced\n' > "${called_file}"; }
  run package_manager::init_alpine
  assert_success
  run cat "${called_file}"
  assert_output "synced"
}

@test "package_manager::init_termux delegates to package_manager::sync_termux_repo" {
  local called_file="${BATS_TEST_TMPDIR}/called"
  function package_manager::sync_termux_repo { printf 'synced\n' > "${called_file}"; }
  run package_manager::init_termux
  assert_success
  run cat "${called_file}"
  assert_output "synced"
}

@test "package_manager::init_fdroid installs droidify when not present" {
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function package_manager::sync_fdroid_repo { printf 'synced\n' >> "${actions_file}"; }
  function package_manager::check_installed_fdroidcl { return 1; }
  function package_manager::install_via_fdroidcl { printf 'installed:%s\n' "$1" >> "${actions_file}"; }
  run package_manager::init_fdroid
  assert_success
  run cat "${actions_file}"
  assert_output $'synced\ninstalled:com.looker.droidify'
}

@test "package_manager::init_macos installs mas when missing" {
  export DRY_RUN='true'
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function package_manager::sync_brew_repo { printf 'synced\n' >> "${actions_file}"; }
  run package_manager::init_macos
  assert_success
  assert_output --partial 'brew install mas'
}

@test "package_manager::init_arch installs paru when missing in dry-run mode" {
  export DRY_RUN='true'
  function dybatpho::is {
    if [[ "$1" == "command" && "$2" == "paru" ]]; then
      return 1
    fi
    __orig_dybatpho_is "$@"
  }
  run package_manager::init_arch
  assert_success
  assert_output --partial 'paru.git'
}

# ---------------------------------------------------------------------------
# package_manager::add_overlay / package_manager::add_fdroid_repo / package_manager::add_brew_tap
# ---------------------------------------------------------------------------

@test "package_manager::add_overlay creates config and syncs repo in dry-run mode" {
  export DRY_RUN='true'
  run package_manager::add_overlay myrepo https://example.com/myrepo.git
  assert_success
  assert_output --partial 'myrepo'
  assert_output --partial 'emaint sync'
}

@test "package_manager::add_fdroid_repo calls fdroidcl repo add in dry-run mode" {
  export DRY_RUN='true'
  run package_manager::add_fdroid_repo myrepo https://example.com/repo
  assert_success
  assert_output --partial 'fdroidcl repo add myrepo https://example.com/repo'
}

@test "package_manager::add_brew_tap calls brew tap in dry-run mode" {
  export DRY_RUN='true'
  run package_manager::add_brew_tap user/repo
  assert_success
  assert_output --partial 'brew tap user/repo'
}

@test "package_manager::add_apt_repo skips when source list already exists" {
  export DRY_RUN='true'
  local list_path="/etc/apt/sources.list.d/sample.list"
  function dybatpho::is {
    if [[ "$1" == "file" && "$2" == "${list_path}" ]]; then return 0; fi
    __orig_dybatpho_is "$@"
  }
  run package_manager::add_apt_repo sample https://packages.example stable main ABCD1234
  assert_success
  refute_output --partial 'keyserver.ubuntu.com'
}

# ---------------------------------------------------------------------------
# package_manager::check_installed_* — stub the underlying commands
# ---------------------------------------------------------------------------

@test "package_manager::check_installed_pacman delegates to pacman -Q" {
  cat > "${HOME}/.local/bin/pacman" << 'EOF'
#!/usr/bin/env bash
[[ "$1" == "-Q" && "$3" == "vim" ]] && exit 0; exit 1
EOF
  chmod +x "${HOME}/.local/bin/pacman"
  run package_manager::check_installed_pacman vim
  assert_success
}

@test "package_manager::check_installed_apk delegates to apk info -e" {
  cat > "${HOME}/.local/bin/apk" << 'EOF'
#!/usr/bin/env bash
[[ "$1" == "info" && "$2" == "-e" && "$4" == "curl" ]] && { printf 'curl\n'; exit 0; }; exit 1
EOF
  chmod +x "${HOME}/.local/bin/apk"
  run package_manager::check_installed_apk curl
  assert_success
}

@test "package_manager::check_installed_flatpak delegates to flatpak list" {
  stub flatpak 'list --app : printf "Name com.example.App stable flathub\n"'
  run package_manager::check_installed_flatpak com.example.App
  assert_success
  unstub flatpak
}

@test "package_manager::check_installed_brew delegates to brew list" {
  stub brew 'list --formula --versions -- mytool : printf "mytool 1.0\n"'
  run package_manager::check_installed_brew mytool
  assert_success
  unstub brew
}

@test "package_manager::check_installed_brew finds a cask that is not a formula" {
  stub brew \
    'list --formula --versions -- firefox : exit 1' \
    'list --cask --versions -- firefox : printf "firefox 1.0\n"'
  run package_manager::check_installed_brew firefox
  assert_success
  unstub brew
}

@test "package_manager::check_installed_dmg checks /Applications for .app bundle" {
  mkdir -p "${BATS_TEST_TMPDIR}/Applications/MyApp.app"
  function find {
    if [[ "$1" == "/Applications" ]]; then
      command find "${BATS_TEST_TMPDIR}/Applications" "${@:2}"
    else
      command find "$@"
    fi
  }
  run package_manager::check_installed_dmg MyApp
  assert_success
}

# ---------------------------------------------------------------------------
# package_manager::install_via_* — dry-run output assertions
# ---------------------------------------------------------------------------

@test "package_manager::install_via_portage prints emerge command in dry-run mode" {
  export DRY_RUN='true'
  run package_manager::install_via_portage app-misc/jq
  assert_success
  assert_output --partial 'emerge --noreplace --ask=n app-misc/jq'
}

@test "package_manager::install_via_pacman prints paru command in dry-run mode" {
  export DRY_RUN='true'
  run package_manager::install_via_pacman neovim
  assert_success
  assert_output --partial 'paru --noconfirm -S --needed --skipreview neovim'
}

@test "package_manager::install_via_apt prints apt install command in dry-run mode" {
  export DRY_RUN='true'
  run package_manager::install_via_apt ripgrep
  assert_success
  assert_output --partial 'apt-get install -y ripgrep'
}

@test "package_manager::install_via_apk prints apk add command in dry-run mode" {
  export DRY_RUN='true'
  run package_manager::install_via_apk curl
  assert_success
  assert_output --partial 'apk add --no-cache --no-interactive curl'
}

@test "package_manager::install_via_termux prints pkg install command in dry-run mode" {
  export DRY_RUN='true'
  run package_manager::install_via_termux git
  assert_success
  assert_output --partial 'pkg install -y git'
}

@test "package_manager::install_via_fdroidcl prints fdroidcl install command in dry-run mode" {
  export DRY_RUN='true'
  run package_manager::install_via_fdroidcl com.example.App
  assert_success
  assert_output --partial 'fdroidcl install com.example.App'
}

@test "package_manager::install_via_brew prints brew install command in dry-run mode" {
  export DRY_RUN='true'
  run package_manager::install_via_brew fzf
  assert_success
  assert_output --partial 'brew install fzf'
}

@test "package_manager::install_via_brew passes brew flags through to the install command" {
  export DRY_RUN='true'
  run package_manager::install_via_brew firefox --cask --HEAD
  assert_success
  assert_output --partial 'brew install --cask --HEAD firefox'
}

@test "package_manager::install_via_mas prints mas install command in dry-run mode" {
  export DRY_RUN='true'
  cat > "${HOME}/.local/bin/mas" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "info" ]]; then printf 'Xcode 14.0\n'; exit 0; fi
exit 0
EOF
  chmod +x "${HOME}/.local/bin/mas"
  run package_manager::install_via_mas 497799835
  assert_success
  assert_output --partial 'mas install 497799835'
}
