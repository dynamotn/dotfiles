#!/bin/bash
# shellcheck disable=2154

#######################################
# @description Sync repositories of Gentoo
#######################################
function _gentoo_sync_repo {
  sudo emerge --sync
}

#######################################
# @description Add repository to Gentoo portage
# @arg $1 string Name of repository
# @arg $2 string URI of the repository
#######################################
function _gentoo_add_repo {
  dybatpho::expect_args repo_name uri -- "$@"
  if [ ! -d "/etc/portage/repos.conf/$repo_name.conf" ]; then
    sudo mkdir -p /etc/portage/repos.conf
    echo "[$repo_name]" | sudo tee /etc/portage/repos.conf/"$repo_name.conf"
    echo "location = /var/db/repos/$repo_name" | sudo tee -a /etc/portage/repos.conf/"$repo_name.conf"
    echo "sync-type = git" | sudo tee -a /etc/portage/repos.conf/"$repo_name.conf"
    echo "sync-uri = $uri" | sudo tee -a /etc/portage/repos.conf/"$repo_name.conf"
    emaint sync --repo "$repo_name" || dybatpho::die "Failed to sync repository $repo_name."
  fi
}

#######################################
# @description Check if a package is installed in Gentoo.
# Need _gentoo_init to be called first to ensure `qlist` is available.
# @arg $1 string Package name
#######################################
function _gentoo_check_installed {
  dybatpho::expect_args package -- "$@"
  qlist -I "$package" > /dev/null
}

#######################################
# @description Install a package in Gentoo
# @arg $1 string Package name
#######################################
function _gentoo_install {
  dybatpho::expect_args package -- "$@"
  dybatpho::dry_run sudo emerge --ask n --noreplace "$package"
}

#######################################
# @description Initialize Gentoo package manager
#######################################
function _gentoo_init {
  _gentoo_sync_repo
  if [ ! -x '/usr/bin/equery' ]; then
    _gentoo_install app-portage/gentoolkit
  fi
  if [ ! -x '/usr/bin/qlist' ]; then
    _gentoo_install app-portage/portage-utils
  fi
}

#######################################
# @description Sync repositories of Arch
#######################################
function _arch_sync_repo {
  if ! command -v paru > /dev/null; then
    sudo pacman -Sy
  else
    paru -Sy
  fi
}

#######################################
# @description Check if a package is installed in Arch
# @arg $1 string Package name
#######################################
function _arch_check_installed {
  dybatpho::expect_args package -- "$@"
  pacman -Qi "$package" > /dev/null
}

#######################################
# @description Install a package in Arch
# @arg $1 string Package name
#######################################
function _arch_install {
  dybatpho::expect_args package -- "$@"
  dybatpho::dry_run paru --noconfirm -S --needed --skipreview "$package"
}

#######################################
# @description Initialize Arch package manager
#######################################
function _arch_init {
  _arch_sync_repo
  if ! command -v paru > /dev/null; then
    sudo pacman -S --needed git base-devel rust
    git clone https://aur.archlinux.org/paru.git /tmp/paru
    cd /tmp/paru || exit
    makepkg -si --noconfirm
    rm -rf /tmp/paru
    sudo pacman -Rscn --noconfirm rust
  fi
}

#######################################
# @description Sync repositories of Ubuntu
#######################################
function _ubuntu_sync_repo {
  sudo apt update
}

#######################################
# @description Add repository of PPA to Ubuntu
# @arg $1 string Name of repository
# @arg $2 string Code of repository
# @arg $3 string Distro version (e.g., focal, bionic)
# @arg $4 string Repository version (e.g., main, universe)
# @arg $5 string GPG key of repository
#######################################
function _ubuntu_add_repo {
  dybatpho::expect_args repo_name repo_code distro_version repo_version key -- "$@"
  if [ ! -f "/etc/apt/sources.list.d/$repo_name.list" ]; then
    echo "deb $repo_code $distro_version $repo_version" | sudo tee /"etc/apt/sources.list.d/$repo_name.list"
    curl -sSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$key" | sudo apt-key add -
  fi
}

#######################################
# @description Check if a package is installed in Ubuntu
# @arg $1 string Package name
#######################################
function _ubuntu_check_installed {
  dybatpho::expect_args package -- "$@"
  dpkg-query -s "$package" > /dev/null 2>&1
}

#######################################
# @description Install a package in Ubuntu
# @arg $1 string Package name
#######################################
function _ubuntu_install {
  dybatpho::expect_args package -- "$@"
  dybatpho::dry_run sudo apt install -y "$package"
}

#######################################
# @description Initialize Ubuntu package manager
#######################################
function _ubuntu_init {
  _ubuntu_sync_repo
}

#######################################
# @description Sync repositories of Alpine
#######################################
function _alpine_sync_repo {
  sudo apk update
}

#######################################
# @description Check if a package is installed in Alpine
# @arg $1 string Package name
#######################################
function _alpine_check_installed {
  dybatpho::expect_args package -- "$@"
  apk info -e "$package" > /dev/null 2>&1
}

#######################################
# @description Install a package in Alpine
# @arg $1 string Package name
#######################################
function _alpine_install {
  dybatpho::expect_args package -- "$@"
  dybatpho::dry_run sudo apk add --no-cache --no-interactive "$package"
}

#######################################
# @description Initialize Alpine package manager
#######################################
function _alpine_init {
  _alpine_sync_repo
}

#######################################
# @description Sync repositories of Termux
#######################################
function _termux_sync_repo {
  pkg update
}

#######################################
# @description Check if a package is installed in Termux
# @arg $1 string Package name
#######################################
function _termux_check_installed {
  dybatpho::expect_args package -- "$@"
  dpkg-query -s "$package" > /dev/null 2>&1
}

#######################################
# @description Install a package in Termux
# @arg $1 string Package name
#######################################
function _termux_install {
  dybatpho::expect_args package -- "$@"
  dybatpho::dry_run pkg install -y "$package"
}

#######################################
# @description Initialize Termux package manager
#######################################
function _termux_init {
  _termux_sync_repo
}

#######################################
# @description Sync repositories of MacOS
#######################################
function _macos_sync_repo {
  brew update
}

#######################################
# @description Check if a package is installed in MacOS via brew
# @arg $1 string Package name
#######################################
function _macos_brew_check_installed {
  dybatpho::expect_args package -- "$@"
  brew ls --versions "$1" > /dev/null
}

#######################################
# @description Check if a package is installed in MacOS via Apple Store.
# Needs `mas` to be installed first.
# @arg $1 string Package name
#######################################
function _macos_mas_check_installed {
  dybatpho::expect_args package -- "$@"
  mas list | grep -q "$package"
}

# @description Check if a package is installed in MacOS via Apple Store
# @arg $1 string Package name
#######################################
function _macos_brew_install {
  dybatpho::expect_args package -- "$@"
  dybatpho::dry_run brew install "$@" "$package"
}

#######################################
# @description Install a package in MacOS via Apple Store
# @arg $1 string Package name
#######################################
function _macos_mas_install {
  dybatpho::expect_args package -- "$@"
  dybatpho::dry_run mas install "$package"
}

#######################################
# @description Initialize MacOS package manager
# and install `mas` for Apple Store apps
#######################################
function _macos_init {
  _macos_sync_repo
  brew install mas
}
