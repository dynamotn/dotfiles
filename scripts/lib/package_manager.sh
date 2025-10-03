#!/usr/bin/env bash
# @file package_manager.sh
# @brief Library `pkg` to manage package via package manager of distros
# @description Library `pkg` to manage package via package manager of distros,
# include repositories, packages

#######################################
# @description Sync repositories of Gentoo
# @noargs
#######################################
function pkg::sync_portage_repo {
  dybatpho::progress "Syncing package repositories"
  dybatpho::dry_run sudo emaint sync --allrepos
}

#######################################
# @description Sync repositories of Arch
# @noargs
#######################################
function pkg::sync_pacman_repo {
  dybatpho::progress "Syncing package repositories"
  if ! dybatpho::is command paru; then
    dybatpho::dry_run sudo pacman -Sy
  else
    dybatpho::dry_run paru -Sy
  fi
}

#######################################
# @description Sync repositories of Ubuntu, Debian...
# @noargs
#######################################
function pkg::sync_apt_repo {
  dybatpho::progress "Syncing package repositories"
  dybatpho::dry_run sudo apt update
}

#######################################
# @description Sync repositories of Alpine
# @noargs
#######################################
function pkg::sync_apk_repo {
  dybatpho::progress "Syncing package repositories"
  dybatpho::dry_run sudo apk update
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
# @description Sync repositories of MacOS
# @noargs
#######################################
function pkg::sync_brew_repo {
  dybatpho::progress "Syncing package repositories"
  dybatpho::dry_run brew update
}

#######################################
# @description Initialize Gentoo package manager
# @noargs
#######################################
function pkg::init_gentoo {
  pkg::sync_portage_repo
  if ! dybatpho::is command equery; then
    dybatpho::progress "Installing \`equery\` for day-to-day package management"
    pkg::install_via_gentoo app-portage/gentoolkit
  fi
  if ! dybatpho::is command qlist; then
    dybatpho::progress "Installing \`qlist\` for querying installed packages"
    pkg::install_via_gentoo app-portage/portage-utils
  fi
}

#######################################
# @description Initialize Arch package manager
# @noargs
#######################################
function pkg::init_arch {
  pkg::sync_pacman_repo
  if ! dybatpho::is command paru; then
    dybatpho::progress "Installing \`paru\` for managing AUR packages"
    dybatpho::dry_run sudo pacman -S --needed --noconfirm git base-devel rust
    dybatpho::create_temp paru ""
    # shellcheck disable=SC2154
    dybatpho::dry_run git clone https://aur.archlinux.org/paru.git "$paru"
    dybatpho::dry_run cd "$paru"
    dybatpho::dry_run makepkg -si --noconfirm
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
  if ! dybatpho::is command mas; then
    dybatpho::progress "Installing \`mas\` for managing Apple Store apps"
    pkg::install_via_macos_brew mas
  fi
}

#######################################
# @description Add repository to Gentoo portage
# @arg $1 string Name of repository
# @arg $2 string URL of the repository
#######################################
function pkg::add_overlay {
  local name url
  dybatpho::expect_args name url -- "$@"
  if [ ! -d "/etc/portage/repos.conf/$name.conf" ]; then
    dybatpho::dry_run sudo mkdir -p /etc/portage/repos.conf
    dybatpho::dry_run eval "echo \"[$name]\" | sudo tee /etc/portage/repos.conf/$name.conf"
    dybatpho::dry_run eval "echo \"location = /var/db/repos/$name\" | sudo tee -a /etc/portage/repos.conf/$name.conf"
    dybatpho::dry_run eval "echo \"sync-type = git\" | sudo tee -a /etc/portage/repos.conf/$name.conf"
    dybatpho::dry_run eval "echo \"sync-uri = $url\" | sudo tee -a /etc/portage/repos.conf/$name.conf"
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
  local path
  if dybatpho::is command termux-setup-storage; then
    path="$PREFIX/etc/apt/sources.list.d/$name.list"
  else
    path="/etc/apt/sources.list.d/$name.list"
  fi
  if ! dybatpho::is file "$path"; then
    dybatpho::debug "Adding repository $name."
    if ! [[ "$key" =~ ^https://.* ]]; then
      key="https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${key#0x}"
    fi
    dybatpho::create_temp temp_key ".gpg"
    # shellcheck disable=SC2154
    dybatpho::dry_run dybatpho::curl_download "$key" "$temp_key"
    dybatpho::dry_run sudo cp "$temp_key" "/etc/apt/keyrings/${name}.gpg"
    dybatpho::dry_run eval "echo \"deb [signed-by=/etc/apt/keyrings/${name}.gpg] ${url} ${suite} ${components}\" | sudo tee \"/etc/apt/sources.list.d/$name.list\""
  else
    dybatpho::debug "Repository $name already exists, skipping."
  fi
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
  qlist -I "$package" > /dev/null
}

#######################################
# @description Check if a package is installed on Arch
# @arg $1 string Package name
#######################################
function pkg::check_installed_pacman {
  local package
  dybatpho::expect_args package -- "$@"
  pacman -Qi "$package" > /dev/null
}

#######################################
# @description Check if a package is installed on Ubuntu, Debian, Termux...
# @arg $1 string Package name
#######################################
function pkg::check_installed_apt {
  local package
  dybatpho::expect_args package -- "$@"
  dpkg-query -s "$package" > /dev/null 2>&1
}

#######################################
# @description Check if a package is installed on Alpine
# @arg $1 string Package name
#######################################
function pkg::check_installed_apk {
  local package
  dybatpho::expect_args package -- "$@"
  apk info -e "$package" > /dev/null 2>&1
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
  grep -q "^$package$" <(brew ls -1)
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
  dybatpho::progress "Installing package $package"
  dybatpho::dry_run sudo emerge --ask n --noreplace "$package"
}

#######################################
# @description Install a package in Arch
# @arg $1 string Package name
#######################################
function pkg::install_via_pacman {
  local package
  dybatpho::expect_args package -- "$@"
  dybatpho::progress "Installing package $package"
  dybatpho::dry_run paru --noconfirm -S --needed --skipreview "$package"
}

#######################################
# @description Install a package in Ubuntu
# @arg $1 string Package name
#######################################
function pkg::install_via_apt {
  local package
  dybatpho::expect_args package -- "$@"
  dybatpho::progress "Installing package $package"
  dybatpho::dry_run sudo apt install -y "$package"
}

#######################################
# @description Install a package in Alpine
# @arg $1 string Package name
#######################################
function pkg::install_via_apk {
  local package
  dybatpho::expect_args package -- "$@"
  dybatpho::progress "Installing package $package"
  dybatpho::dry_run sudo apk add --no-cache --no-interactive "$package"
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
# @description Check if a package is installed on MacOS via Apple Store
# @arg $1 string Package name
#######################################
function pkg::install_via_brew {
  local package
  dybatpho::expect_args package -- "$@"
  dybatpho::progress "Installing package $package"
  dybatpho::dry_run brew install "$@" "$package"
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
