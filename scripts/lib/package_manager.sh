#!/usr/bin/env bash
# @file package_manager.sh
# @brief Library `pkg` to manage package via package manager of distros
# @description Library `pkg` to manage package via package manager of distros,
# include repositories, packages.
#
# The `pkg` module of dybatpho already knows how to detect, query, update and
# install with `apt`, `apk`, `brew`, `dnf`, `pacman` and `emerge`, so those
# managers are driven through it instead of hand-written commands. Managers it
# doesn't support (Termux's `pkg`, `fdroidcl`, `flatpak`, `mas`, `.dmg` files)
# and Arch's AUR helper `paru` keep their own implementation here.
dybatpho::load network pkg

#######################################
# @description Run a dybatpho `pkg` command against an explicit package manager
# instead of the one detected on this machine. The override lives in a subshell,
# so it never leaks into the caller.
# @arg $1 string Package manager name, one of `dybatpho::pkg_supported`
# @arg $@ string Command and its arguments
# @exitcode The exit code of the command
#######################################
function __pkg_with_manager {
  local manager
  dybatpho::expect_args manager -- "$@"
  shift
  (
    export DYBATPHO_PKG_MANAGER="${manager}"
    "$@"
  )
}

#######################################
# @description Sync repositories of a package manager supported by dybatpho
# @arg $1 string Package manager name, one of `dybatpho::pkg_supported`
#######################################
function pkg::sync_repo {
  local manager
  dybatpho::expect_args manager -- "$@"
  dybatpho::progress "Syncing package repositories"
  __pkg_with_manager "$manager" dybatpho::pkg_update --force
}

#######################################
# @description Check if a package is installed, with a package manager
# supported by dybatpho
# @arg $1 string Package manager name, one of `dybatpho::pkg_supported`
# @arg $2 string Package name
#######################################
function pkg::check_installed {
  local manager package
  dybatpho::expect_args manager package -- "$@"
  __pkg_with_manager "$manager" dybatpho::pkg_installed "$package"
}

#######################################
# @description Install packages with a package manager supported by dybatpho
# @arg $1 string Package manager name, one of `dybatpho::pkg_supported`
# @arg $@ string Package names, and `--arg`/`-a` options handed to the manager itself
#######################################
function pkg::install {
  local manager
  dybatpho::expect_args manager -- "$@"
  shift
  local -a options=() packages=()
  while (($#)); do
    case "$1" in
      -a | --arg)
        (($# > 1)) || dybatpho::die "pkg::install: expected a value after $1"
        options+=("$1" "$2")
        shift
        ;;
      *) packages+=("$1") ;;
    esac
    shift
  done
  ((${#packages[@]})) || dybatpho::die "pkg::install: expected at least one package"
  dybatpho::progress "Installing package ${packages[*]}"
  __pkg_with_manager "$manager" dybatpho::pkg_install --force "${options[@]}" -- "${packages[@]}"
}

#######################################
# @description Make sure a command is available, installing the package that
# provides it with a package manager supported by dybatpho
# @arg $1 string Package manager name, one of `dybatpho::pkg_supported`
# @arg $2 string Command that must be available
# @arg $3 string Package providing the command
#######################################
function pkg::require {
  local manager command package
  dybatpho::expect_args manager command package -- "$@"
  __pkg_with_manager "$manager" dybatpho::pkg_require --force "$command" "${manager}:${package}"
}

#######################################
# @description Sync repositories of Gentoo
# @noargs
#######################################
function pkg::sync_portage_repo {
  pkg::sync_repo emerge
}

#######################################
# @description Sync repositories of Arch
# @noargs
#######################################
function pkg::sync_pacman_repo {
  # `paru` also refreshes the AUR metadata, so it wins when it is installed.
  if ! dybatpho::is command paru; then
    pkg::sync_repo pacman
  else
    dybatpho::progress "Syncing package repositories"
    dybatpho::dry_run paru -Sy
  fi
}

#######################################
# @description Sync repositories of Ubuntu, Debian...
# @noargs
#######################################
function pkg::sync_apt_repo {
  pkg::sync_repo apt
}

#######################################
# @description Sync repositories of Alpine
# @noargs
#######################################
function pkg::sync_apk_repo {
  pkg::sync_repo apk
}

#######################################
# @description Sync repositories of Termux
# @noargs
#######################################
function pkg::sync_termux_repo {
  dybatpho::progress "Syncing package repositories"
  dybatpho::dry_run pkg update
}

#######################################
# @description Sync repositories of F-Droid
# @noargs
#######################################
function pkg::sync_fdroid_repo {
  dybatpho::progress "Syncing application repositories"
  dybatpho::dry_run fdroidcl update
}

#######################################
# @description Sync repositories of MacOS
# @noargs
#######################################
function pkg::sync_brew_repo {
  pkg::sync_repo brew
}

#######################################
# @description Initialize Gentoo package manager
# @noargs
#######################################
function pkg::init_gentoo {
  pkg::sync_portage_repo
  # `qlist` and `equery` are also what `dybatpho::pkg_installed` queries on emerge.
  pkg::require emerge qlist app-portage/portage-utils
  pkg::require emerge equery app-portage/gentoolkit
}

#######################################
# @description Initialize Arch package manager
# @noargs
#######################################
function pkg::init_arch {
  pkg::sync_pacman_repo
  if ! dybatpho::is command paru; then
    dybatpho::progress "Installing \`paru\` for managing AUR packages"
    pkg::install pacman git base-devel rust
    dybatpho::create_temp_dir paru
    # shellcheck disable=SC2154
    dybatpho::dry_run git clone https://aur.archlinux.org/paru.git "$paru"
    dybatpho::dry_run bash -c "cd \"${paru}\" && makepkg -si --noconfirm"
    dybatpho::dry_run sudo pacman -Rscn --noconfirm rust
  fi
}

#######################################
# @description Initialize Ubuntu package manager
# @noargs
#######################################
function pkg::init_ubuntu {
  pkg::sync_apt_repo
}

#######################################
# @description Initialize Alpine package manager
#######################################
function pkg::init_alpine {
  pkg::sync_apk_repo
}

#######################################
# @description Initialize Termux package manager
# @noargs
#######################################
function pkg::init_termux {
  pkg::sync_termux_repo
}

#######################################
# @description Initialize F-Droid application manager
# @noargs
#######################################
function pkg::init_fdroid {
  pkg::sync_fdroid_repo
  pkg::check_installed_fdroidcl com.looker.droidify \
    || pkg::install_via_fdroidcl com.looker.droidify
}

#######################################
# @description Initialize Flatpak package manager
# @noargs
#######################################
function pkg::init_flatpak {
  pkg::add_flatpak_repo flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  pkg::install_via_flatpak com.github.tchx84.Flatseal flathub
}

#######################################
# @description Initialize MacOS package manager
# and install `mas` for Apple Store apps
# @noargs
#######################################
function pkg::init_macos {
  pkg::sync_brew_repo
  pkg::require brew mas mas
}

#######################################
# @description Add repository to Gentoo portage
# @arg $1 string Name of repository
# @arg $2 string URL of the repository
#######################################
function pkg::add_overlay {
  local name url
  dybatpho::expect_args name url -- "$@"
  if ! dybatpho::is file "/etc/portage/repos.conf/${name}.conf"; then
    dybatpho::dry_run sudo mkdir -p /etc/portage/repos.conf
    dybatpho::create_temp repo_conf ".conf"
    # shellcheck disable=SC2154
    cat > "${repo_conf}" << EOF
[${name}]
location = /var/db/repos/${name}
sync-type = git
sync-uri = ${url}
EOF
    dybatpho::dry_run sudo cp "${repo_conf}" "/etc/portage/repos.conf/${name}.conf"
    dybatpho::dry_run sudo emaint sync --yes --repo "$name" || dybatpho::die "Failed to sync repository $name"
  fi
}

#######################################
# @description Add repository of APT (include PPA) to Ubuntu, Debian, Termux...
# @arg $1 string Name of repository
# @arg $2 string URL of repository
# @arg $3 string Suite of repository (e.g., bionic, focal, stable)
# @arg $4 string Components (e.g., main, universe)
# @arg $5 string URL of repository's GPG apt-key or fingerprint (can be with or without 0x prefix)
#######################################
function pkg::add_apt_repo {
  local name url suite components key
  dybatpho::expect_args name url suite components key -- "$@"
  local path gpg_path
  gpg_path="$(dybatpho::path_join "/etc/apt/trusted.gpg.d" "${name}.gpg")"
  if dybatpho::is command termux-setup-storage; then
    path="$(dybatpho::path_join "$PREFIX" "etc" "apt" "sources.list.d" "${name}.list")"
  else
    path="$(dybatpho::path_join "/etc/apt/sources.list.d" "${name}.list")"
  fi
  if ! dybatpho::is file "$path"; then
    dybatpho::debug "Adding repository $name."
    if ! [[ "$key" =~ ^https://.* ]]; then
      key="https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x${key#0x}"
    fi
    dybatpho::create_temp temp_key ".gpg"
    # shellcheck disable=SC2154
    dybatpho::curl_download "$key" "$temp_key"
    if ! [[ "$key" =~ ^https://.* ]]; then
      dybatpho::dry_run sudo cp "$temp_key" "$gpg_path"
    else
      dybatpho::dry_run sudo gpg --dearmor --yes -o "$gpg_path" "$temp_key"
    fi
    dybatpho::create_temp repo_list ".list"
    # shellcheck disable=SC2154
    printf '%s\n' "deb [signed-by=${gpg_path}] ${url} ${suite} ${components}" > "${repo_list}"
    dybatpho::dry_run sudo cp "${repo_list}" "${path}"
  else
    dybatpho::debug "Repository $name already exists, skipping."
  fi
}

#######################################
# @description Add repository of Fdroid
# @arg $1 string Name of repository
# @arg $2 string URL of the repository
#######################################
function pkg::add_fdroid_repo {
  local name url
  dybatpho::expect_args name url -- "$@"
  dybatpho::dry_run fdroidcl repo add "$name" "$url"
}

#######################################
# @description Add repository of Flatpak
# @arg $1 string Name of repository
# @arg $2 string URL of the repository
#######################################
function pkg::add_flatpak_repo {
  local name url
  dybatpho::expect_args name url -- "$@"
  if ! dybatpho::is command flatpak; then
    dybatpho::die "Flatpak is not installed. Please install it first."
  fi
  if ! flatpak remote-list | grep -q "^$name$"; then
    dybatpho::progress "Adding Flatpak repository $name"
    dybatpho::dry_run flatpak remote-add --user --if-not-exists "$name" "$url"
  else
    dybatpho::debug "Flatpak repository $name already exists, skipping."
  fi
}

#######################################
# @description Add a Homebrew tap
# @arg $1 string Repository name
#######################################
function pkg::add_brew_tap {
  local name
  dybatpho::expect_args name -- "$@"

  dybatpho::progress "Adding Homebrew tap $name"
  dybatpho::dry_run brew tap "$name"
}

#######################################
# @description Check if a package is installed on Gentoo.
# Need pkg::init_gentoo to be called first to ensure `qlist` is available.
# @arg $1 string Package name
#######################################
function pkg::check_installed_portage {
  local package
  dybatpho::expect_args package -- "$@"
  pkg::check_installed emerge "$package"
}

#######################################
# @description Check if a package is installed on Arch
# @arg $1 string Package name
#######################################
function pkg::check_installed_pacman {
  local package
  dybatpho::expect_args package -- "$@"
  pkg::check_installed pacman "$package"
}

#######################################
# @description Check if a package is installed on Ubuntu, Debian, Termux...
# @arg $1 string Package name
#######################################
function pkg::check_installed_apt {
  local package
  dybatpho::expect_args package -- "$@"
  pkg::check_installed apt "$package"
}

#######################################
# @description Check if a package is installed on Alpine
# @arg $1 string Package name
#######################################
function pkg::check_installed_apk {
  local package
  dybatpho::expect_args package -- "$@"
  pkg::check_installed apk "$package"
}

#######################################
# @description Check if a package is installed on Android via fdroidcl
# @arg $1 string Application ID
#######################################
function pkg::check_installed_fdroidcl {
  local app_id
  dybatpho::expect_args app_id -- "$@"
  cmd package list packages 2> /dev/null | grep -wq "$app_id"
}

#######################################
# @description Check if a package is installed via Flatpak
# @arg $1 string Application ID
#######################################
function pkg::check_installed_flatpak {
  local package
  dybatpho::expect_args package -- "$@"
  flatpak list --app | awk '{print $2}' | grep -q "^$package$"
}

#######################################
# @description Check if a package is installed on MacOS via brew
# @arg $1 string Package name
#######################################
function pkg::check_installed_brew {
  local package
  dybatpho::expect_args package -- "$@"
  pkg::check_installed brew "$package"
}

#######################################
# @description Check if a package is installed on MacOS via Apple Store.
# Needs `mas` to be installed first.
# @arg $1 string Apple Store app ID
#######################################
function pkg::check_installed_mas {
  local app_id
  dybatpho::expect_args app_id -- "$@"
  mas list | awk '{print $1}' | grep -wq "$app_id"
}

#######################################
# @description Check if a package is installed on MacOS via download .dmg file
# and copy to /Applications
# @arg $1 string Name of application
#######################################
function pkg::check_installed_dmg {
  local app_name
  dybatpho::expect_args app_name -- "$@"
  find /Applications -maxdepth 1 -name "${app_name}.app" -print -quit | grep -q "${app_name}.app"
}

#######################################
# @description Install a package in Gentoo
# @arg $1 string Package name
#######################################
function pkg::install_via_portage {
  local package
  dybatpho::expect_args package -- "$@"
  pkg::install emerge "$package"
}

#######################################
# @description Install a package in Arch
# @arg $1 string Package name
#######################################
function pkg::install_via_pacman {
  local package
  dybatpho::expect_args package -- "$@"
  dybatpho::progress "Installing package $package"
  # `dybatpho::pkg_install` drives `pacman`, which can't build AUR packages, so
  # `paru` stays in charge here.
  dybatpho::dry_run paru --noconfirm -S --needed --skipreview "$package"
}

#######################################
# @description Install a package in Ubuntu
# @arg $1 string Package name
#######################################
function pkg::install_via_apt {
  local package
  dybatpho::expect_args package -- "$@"
  pkg::install apt "$package"
}

#######################################
# @description Install a package in Alpine
# @arg $1 string Package name
#######################################
function pkg::install_via_apk {
  local package
  dybatpho::expect_args package -- "$@"
  # No index is kept on these machines, and nothing is watching the install.
  pkg::install apk --arg --no-cache --arg --no-interactive "$package"
}

#######################################
# @description Install a package in Termux
# @arg $1 string Package name
#######################################
function pkg::install_via_termux {
  local package
  dybatpho::expect_args package -- "$@"
  dybatpho::progress "Installing package $package"
  dybatpho::dry_run pkg install -y "$package"
}

#######################################
# @description Install a package in Android
# @arg $1 string Application ID
#######################################
function pkg::install_via_fdroidcl {
  local app_id
  dybatpho::expect_args app_id -- "$@"
  dybatpho::progress "Installing application $app_id"
  dybatpho::dry_run fdroidcl install "$app_id"
}

#######################################
# @description Install a flatpak application
# @arg $1 string Application ID
# @arg $2 string Repository name
#######################################
function pkg::install_via_flatpak {
  local app_id repo
  dybatpho::expect_args app_id repo -- "$@"
  dybatpho::progress "Installing Flatpak app $app_id from $repo repo"
  dybatpho::dry_run flatpak install -y --user "$repo" "$app_id"
}

#######################################
# @description Install a package in MacOS via Homebrew
# @arg $1 string Package name
# @arg $@ string Flags of `brew install`, such as `--cask` or `--HEAD`
#######################################
function pkg::install_via_brew {
  local package
  dybatpho::expect_args package -- "$@"
  shift
  local -a options=()
  local flag
  for flag in "$@"; do
    options+=(--arg "$flag")
  done
  pkg::install brew "${options[@]}" "$package"
}

#######################################
# @description Install a package in MacOS via Apple Store
# @arg $1 string Apple Store app ID
#######################################
function pkg::install_via_mas {
  local app_id
  dybatpho::expect_args app_id -- "$@"
  dybatpho::progress "Installing app $(mas info "$app_id" | head -n 1)"
  dybatpho::dry_run mas install "$app_id"
}

#######################################
# @description Install a package in MacOS via download .dmg file
# and copy to /Applications
# @arg $1 string Name of application
# @arg $2 string URL to download
#######################################
function pkg::install_via_dmg {
  local app_name url
  dybatpho::expect_args app_name url -- "$@"
  dybatpho::progress "Installing app $app_name"
  dybatpho::create_temp temp_file ".dmg"
  # shellcheck disable=SC2154
  dybatpho::curl_download "$url" "$temp_file"
  local mount_dir
  mount_dir=$(hdiutil mount -plist "$temp_file" | grep -oE '/Volumes/[^"<]+' | head -n 1)
  sudo cp -r "${mount_dir}/${app_name}.app" /Applications
  sudo hdiutil unmount "$mount_dir"
}
