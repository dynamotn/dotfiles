#!/bin/bash
# shellcheck disable=2154

function _gentoo_sync_repo {
  sudo emerge --sync
}

function _gentoo_add_repo {
  dybatpho::expect_args repo_name uri -- "$@"
  if [ ! -d "/etc/portage/repos.conf/$repo_name.conf" ]; then
    sudo mkdir -p /etc/portage/repos.conf
    echo "[$repo_name]" | sudo tee /etc/portage/repos.conf/"$repo_name.conf"
    echo "location = /var/db/repos/$repo_name" | sudo tee -a /etc/portage/repos.conf/"$repo_name.conf"
    echo "sync-type = git" | sudo tee -a /etc/portage/repos.conf/"$repo_name.conf"
    echo "sync-uri = $uri" | sudo tee -a /etc/portage/repos.conf/"$repo_name.conf"
  fi
}

function _gentoo_check_installed {
  dybatpho::expect_args package -- "$@"
  if [ ! -x '/usr/bin/qlist' ]; then
    echo >&2 ":: Error: Must install app-portage/portage-utils first."
  fi
  qlist -I "$package" > /dev/null
}

function _gentoo_install {
  dybatpho::expect_args package -- "$@"
  dybatpho::dry_run sudo emerge --ask n --noreplace "$package"
}

function _gentoo_init {
  _gentoo_sync_repo
  _gentoo_install app-portage/gentoolkit
  _gentoo_install app-portage/portage-utils
  _gentoo_install app-eselect/eselect-repository
  sudo eselect repository add dynamo git https://github.com/dynamotn/overlay.git
}

function _arch_sync_repo {
  if ! command -v paru > /dev/null; then
    sudo pacman -Sy
  else
    paru -Sy
  fi
}

function _arch_check_installed {
  dybatpho::expect_args package -- "$@"
  pacman -Qi "$package" > /dev/null
}

function _arch_install {
  dybatpho::expect_args package -- "$@"
  dybatpho::dry_run paru --noconfirm -S --needed --skipreview "$package"
}

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

function _ubuntu_sync_repo {
  sudo apt update
}

function _ubuntu_add_repo {
  dybatpho::expect_args repo_name repo_code distro_version repo_version key -- "$@"
  if [ ! -f "/etc/apt/sources.list.d/$repo_name.list" ]; then
    echo "deb $repo_code $distro_version $repo_version" | sudo tee /"etc/apt/sources.list.d/$repo_name.list"
    curl -sSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$key" | sudo apt-key add -
  fi
}

function _ubuntu_check_installed {
  dybatpho::expect_args package -- "$@"
  dpkg-query -s "$package" > /dev/null 2>&1
}

function _ubuntu_install {
  dybatpho::expect_args package -- "$@"
  dybatpho::dry_run sudo apt install -y "$package"
}

function _ubuntu_init {
  _ubuntu_sync_repo
}

function _termux_sync_repo {
  pkg update
}

function _termux_check_installed {
  dybatpho::expect_args package -- "$@"
  dpkg-query -s "$package" > /dev/null 2>&1
}

function _termux_install {
  dybatpho::expect_args package -- "$@"
  dybatpho::dry_run pkg install -y "$package"
}

function _termux_init {
  _termux_sync_repo
}

function _macos_sync_repo {
  brew update
}

function _macos_init {
  _macos_sync_repo
  brew install mas
}

function _macos_brew_check_installed {
  dybatpho::expect_args package -- "$@"
  brew ls --versions "$1" > /dev/null
}

function _macos_mas_check_installed {
  dybatpho::expect_args package -- "$@"
  mas list | grep -q "$package"
}

function _macos_brew_install {
  dybatpho::expect_args package -- "$@"
  dybatpho::dry_run brew install "$@" "$package"
}

function _macos_mas_install {
  dybatpho::expect_args package -- "$@"
  dybatpho::dry_run mas install "$package"
}
