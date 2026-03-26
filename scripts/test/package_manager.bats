setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/package_manager.sh"
}

@test "pkg::add_apt_repo converts fingerprints to keyserver URLs in dry-run mode" {
  export DRY_RUN='true'

  run pkg::add_apt_repo sample https://packages.example stable main ABCD1234
  assert_success
  assert_output --partial 'https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0xABCD1234'
  assert_output --partial '/etc/apt/trusted.gpg.d/sample.gpg'
  assert_output --partial '/etc/apt/sources.list.d/sample.list'
}

@test "pkg::add_flatpak_repo adds a missing remote in dry-run mode" {
  export DRY_RUN='true'
  stub flatpak ': if [ "$1" = "remote-list" ]; then exit 0; fi'

  run pkg::add_flatpak_repo flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  assert_success
  assert_output --partial 'flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo'
  unstub flatpak
}

@test "pkg::check_installed_apt delegates to dpkg-query" {
  cat > "${HOME}/.local/bin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-s" && "$2" == "sample" ]]; then
  exit 0
fi
exit 1
EOF
  chmod +x "${HOME}/.local/bin/dpkg-query"

  run pkg::check_installed_apt sample
  assert_success
}

@test "pkg::install_via_flatpak prints the install command in dry-run mode" {
  export DRY_RUN='true'

  run pkg::install_via_flatpak com.example.App flathub
  assert_success
  assert_output --partial 'flatpak install -y --user flathub com.example.App'
}

@test "pkg::init_flatpak wires repository setup and Flatseal install" {
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function pkg::add_flatpak_repo { printf 'repo:%s|%s\n' "$1" "$2" >> "${actions_file}"; }
  function pkg::install_via_flatpak { printf 'install:%s|%s\n' "$1" "$2" >> "${actions_file}"; }

  run pkg::init_flatpak
  assert_success
  run cat "${actions_file}"
  assert_success
  assert_output $'repo:flathub|https://dl.flathub.org/repo/flathub.flatpakrepo\ninstall:com.github.tchx84.Flatseal|flathub'
}

# ---------------------------------------------------------------------------
# pkg::sync_* — each prints a progress message and runs the sync command
# ---------------------------------------------------------------------------

@test "pkg::sync_portage_repo prints progress and calls emaint in dry-run mode" {
  export DRY_RUN='true'
  run pkg::sync_portage_repo
  assert_success
  assert_output --partial 'emaint sync --allrepos'
}

@test "pkg::sync_pacman_repo uses paru when available" {
  export DRY_RUN='true'
  cat > "${HOME}/.local/bin/paru" << 'EOF'
#!/usr/bin/env bash
echo "paru $*"
EOF
  chmod +x "${HOME}/.local/bin/paru"
  run pkg::sync_pacman_repo
  assert_success
  assert_output --partial 'paru -Sy'
}

@test "pkg::sync_pacman_repo falls back to pacman when paru is missing" {
  export DRY_RUN='true'
  run pkg::sync_pacman_repo
  assert_success
  assert_output --partial 'pacman -Sy'
}

@test "pkg::sync_apt_repo calls apt update in dry-run mode" {
  export DRY_RUN='true'
  run pkg::sync_apt_repo
  assert_success
  assert_output --partial 'apt update'
}

@test "pkg::sync_apk_repo calls apk update in dry-run mode" {
  export DRY_RUN='true'
  run pkg::sync_apk_repo
  assert_success
  assert_output --partial 'apk update'
}

@test "pkg::sync_termux_repo calls pkg update in dry-run mode" {
  export DRY_RUN='true'
  run pkg::sync_termux_repo
  assert_success
  assert_output --partial 'pkg update'
}

@test "pkg::sync_fdroid_repo calls fdroidcl update in dry-run mode" {
  export DRY_RUN='true'
  run pkg::sync_fdroid_repo
  assert_success
  assert_output --partial 'fdroidcl update'
}

@test "pkg::sync_brew_repo calls brew update in dry-run mode" {
  export DRY_RUN='true'
  run pkg::sync_brew_repo
  assert_success
  assert_output --partial 'brew update'
}

@test "pkg::sync_zerobrew_repo succeeds without error" {
  run pkg::sync_zerobrew_repo
  assert_success
}

# ---------------------------------------------------------------------------
# pkg::init_* — delegate to sync + optional install
# ---------------------------------------------------------------------------

@test "pkg::init_ubuntu delegates to pkg::sync_apt_repo" {
  local called_file="${BATS_TEST_TMPDIR}/called"
  function pkg::sync_apt_repo { printf 'synced\n' > "${called_file}"; }
  run pkg::init_ubuntu
  assert_success
  run cat "${called_file}"
  assert_output "synced"
}

@test "pkg::init_alpine delegates to pkg::sync_apk_repo" {
  local called_file="${BATS_TEST_TMPDIR}/called"
  function pkg::sync_apk_repo { printf 'synced\n' > "${called_file}"; }
  run pkg::init_alpine
  assert_success
  run cat "${called_file}"
  assert_output "synced"
}

@test "pkg::init_termux delegates to pkg::sync_termux_repo" {
  local called_file="${BATS_TEST_TMPDIR}/called"
  function pkg::sync_termux_repo { printf 'synced\n' > "${called_file}"; }
  run pkg::init_termux
  assert_success
  run cat "${called_file}"
  assert_output "synced"
}

@test "pkg::init_fdroid installs droidify when not present" {
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function pkg::sync_fdroid_repo { printf 'synced\n' >> "${actions_file}"; }
  function pkg::check_installed_fdroidcl { return 1; }
  function pkg::install_via_fdroidcl { printf 'installed:%s\n' "$1" >> "${actions_file}"; }
  run pkg::init_fdroid
  assert_success
  run cat "${actions_file}"
  assert_output $'synced\ninstalled:com.looker.droidify'
}

@test "pkg::init_macos installs mas when missing" {
  export DRY_RUN='true'
  local actions_file="${BATS_TEST_TMPDIR}/actions"
  function pkg::sync_brew_repo { printf 'synced\n' >> "${actions_file}"; }
  function pkg::sync_zerobrew_repo { printf 'zerobrew-synced\n' >> "${actions_file}"; }
  run pkg::init_macos
  assert_success
  assert_output --partial 'zb install mas'
}

@test "pkg::init_arch installs paru when missing in dry-run mode" {
  export DRY_RUN='true'
  run pkg::init_arch
  assert_success
  assert_output --partial 'paru.git'
}

# ---------------------------------------------------------------------------
# pkg::add_overlay / pkg::add_fdroid_repo / pkg::add_brew_tap
# ---------------------------------------------------------------------------

@test "pkg::add_overlay creates config and syncs repo in dry-run mode" {
  export DRY_RUN='true'
  run pkg::add_overlay myrepo https://example.com/myrepo.git
  assert_success
  assert_output --partial 'myrepo'
  assert_output --partial 'emaint sync'
}

@test "pkg::add_fdroid_repo calls fdroidcl repo add in dry-run mode" {
  export DRY_RUN='true'
  run pkg::add_fdroid_repo myrepo https://example.com/repo
  assert_success
  assert_output --partial 'fdroidcl repo add myrepo https://example.com/repo'
}

@test "pkg::add_brew_tap calls brew tap in dry-run mode" {
  export DRY_RUN='true'
  run pkg::add_brew_tap user/repo
  assert_success
  assert_output --partial 'brew tap user/repo'
}

@test "pkg::add_apt_repo skips when source list already exists" {
  export DRY_RUN='true'
  local list_path="/etc/apt/sources.list.d/sample.list"
  function dybatpho::is {
    if [[ "$1" == "file" && "$2" == "${list_path}" ]]; then return 0; fi
    command dybatpho::is "$@"
  }
  run pkg::add_apt_repo sample https://packages.example stable main ABCD1234
  assert_success
  refute_output --partial 'keyserver.ubuntu.com'
}

# ---------------------------------------------------------------------------
# pkg::check_installed_* — stub the underlying commands
# ---------------------------------------------------------------------------

@test "pkg::check_installed_pacman delegates to pacman -Qi" {
  cat > "${HOME}/.local/bin/pacman" << 'EOF'
#!/usr/bin/env bash
[[ "$1" == "-Qi" && "$2" == "vim" ]] && exit 0; exit 1
EOF
  chmod +x "${HOME}/.local/bin/pacman"
  run pkg::check_installed_pacman vim
  assert_success
}

@test "pkg::check_installed_apk delegates to apk info -e" {
  cat > "${HOME}/.local/bin/apk" << 'EOF'
#!/usr/bin/env bash
[[ "$1" == "info" && "$2" == "-e" && "$3" == "curl" ]] && exit 0; exit 1
EOF
  chmod +x "${HOME}/.local/bin/apk"
  run pkg::check_installed_apk curl
  assert_success
}

@test "pkg::check_installed_flatpak delegates to flatpak list" {
  stub flatpak 'list --app : printf "Name com.example.App stable flathub\n"'
  run pkg::check_installed_flatpak com.example.App
  assert_success
  unstub flatpak
}

@test "pkg::check_installed_brew delegates to brew ls" {
  stub brew 'ls -1 : printf "wget\ngit\nmytool\n"'
  run pkg::check_installed_brew mytool
  assert_success
  unstub brew
}

@test "pkg::check_installed_dmg checks /Applications for .app bundle" {
  mkdir -p "${BATS_TEST_TMPDIR}/Applications/MyApp.app"
  function find {
    if [[ "$1" == "/Applications" ]]; then
      command find "${BATS_TEST_TMPDIR}/Applications" "${@:2}"
    else
      command find "$@"
    fi
  }
  run pkg::check_installed_dmg MyApp
  assert_success
}

# ---------------------------------------------------------------------------
# pkg::install_via_* — dry-run output assertions
# ---------------------------------------------------------------------------

@test "pkg::install_via_portage prints emerge command in dry-run mode" {
  export DRY_RUN='true'
  run pkg::install_via_portage app-misc/jq
  assert_success
  assert_output --partial 'emerge --ask n --noreplace app-misc/jq'
}

@test "pkg::install_via_pacman prints paru command in dry-run mode" {
  export DRY_RUN='true'
  run pkg::install_via_pacman neovim
  assert_success
  assert_output --partial 'paru --noconfirm -S --needed --skipreview neovim'
}

@test "pkg::install_via_apt prints apt install command in dry-run mode" {
  export DRY_RUN='true'
  run pkg::install_via_apt ripgrep
  assert_success
  assert_output --partial 'apt install -y ripgrep'
}

@test "pkg::install_via_apk prints apk add command in dry-run mode" {
  export DRY_RUN='true'
  run pkg::install_via_apk curl
  assert_success
  assert_output --partial 'apk add --no-cache --no-interactive curl'
}

@test "pkg::install_via_termux prints pkg install command in dry-run mode" {
  export DRY_RUN='true'
  run pkg::install_via_termux git
  assert_success
  assert_output --partial 'pkg install -y git'
}

@test "pkg::install_via_fdroidcl prints fdroidcl install command in dry-run mode" {
  export DRY_RUN='true'
  run pkg::install_via_fdroidcl com.example.App
  assert_success
  assert_output --partial 'fdroidcl install com.example.App'
}

@test "pkg::install_via_brew prints brew install command in dry-run mode" {
  export DRY_RUN='true'
  run pkg::install_via_brew fzf
  assert_success
  assert_output --partial 'brew install fzf'
}

@test "pkg::install_via_zerobrew prints zb install command in dry-run mode" {
  export DRY_RUN='true'
  run pkg::install_via_zerobrew fzf
  assert_success
  assert_output --partial 'zb install fzf'
}

@test "pkg::check_installed_zerobrew detects installed package" {
  stub zb 'bundle dump : printf "brew \"wget\"\nbrew \"git\"\nbrew \"mytool\"\n"'
  run pkg::check_installed_zerobrew mytool
  assert_success
  unstub zb
}

@test "pkg::check_installed_zerobrew detects installed cask" {
  stub zb 'bundle dump : printf "brew \"wget\"\ncask \"docker-desktop\"\n"'
  run pkg::check_installed_zerobrew homebrew/cask/docker-desktop
  assert_success
  unstub zb
}

@test "pkg::check_installed_zerobrew detects installed tap formula" {
  stub zb 'bundle dump : printf "brew \"hashicorp/tap/terraform\"\nbrew \"wget\"\n"'
  run pkg::check_installed_zerobrew hashicorp/tap/terraform
  assert_success
  unstub zb
}

@test "pkg::install_via_mas prints mas install command in dry-run mode" {
  export DRY_RUN='true'
  cat > "${HOME}/.local/bin/mas" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "info" ]]; then printf 'Xcode 14.0\n'; exit 0; fi
exit 0
EOF
  chmod +x "${HOME}/.local/bin/mas"
  run pkg::install_via_mas 497799835
  assert_success
  assert_output --partial 'mas install 497799835'
}
