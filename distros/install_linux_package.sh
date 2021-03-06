#!/bin/bash
DIR=$(dirname "$(readlink -f "$0")")
DISTRO=

_detect_distro() {
  grep -qis "$1" /etc/os-release && DISTRO=$1
}

_detect_package_tool() {
  _detect_distro "Gentoo" && return
  _detect_distro "Arch Linux" && return
  _detect_distro "Ubuntu" && return
}

_gentoo_repo_sync() {
  emerge --sync
}

_gentoo_install() {
  if type equery > /dev/null; then
    equery -N list $1 | grep "\[I" && return
  fi
  emerge -uDN $1
}

_gentoo_init() {
  _gentoo_repo_sync
  _gentoo_install app-portage/gentoolkit
  _gentoo_install app-portage/layman
}

_gentoo_run() {
  local is_first_file=true
  while IFS=, read -r package repo; do
    $is_first_file && is_first_file=false && continue

    if [ -z "$repo" ]; then
      layman -l | grep -qis " $repo " ||
        if [ "$repo" = "dynamo" ]; then
          layman -o https://raw.githubusercontent.com/dynamotn/overlay/master/repositories.xml -f -a dynamo
        else
          layman -a "$repo"
        fi
    fi

    _gentoo_install "$package"
  done < $DIR/gentoo.csv
}

_arch_repo_sync() {
  if ! command -v yay > /dev/null; then
    sudo pacman -Sy
  else
    yay -Sy
  fi
}

_arch_install() {
  yay --noconfirm -S --needed --answerclean All --answerdiff None $1
}

_arch_init() {
  _arch_repo_sync
  if ! command -v yay > /dev/null; then
    sudo pacman -S --needed git base-devel
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay
    makepkg -si --noconfirm
    rm -rf /tmp/yay
  fi
}

_arch_run() {
  local is_first_file=true
  while IFS=, read -r package; do
    $is_first_file && is_first_file=false && continue
    _arch_install "$package"
  done < $DIR/arch.csv
}

_ubuntu_repo_sync() {
  apt update
}

_ubuntu_install() {
  apt install -y $1
}

_ubuntu_init() {
  _ubuntu_repo_sync
}

_ubuntu_run() {
  local is_first_file=true
  while IFS=, read -r package repo repo_name distro_version repo_version key; do
    $is_first_file && is_first_file=false && continue

    if [ ! -z "$repo" ]; then
      test -z "$repo_name" && repo_name=$package
      test -z "$distro_version" && distro_version=$(grep -is UBUNTU_CODENAME /etc/os-release | cut -d= -f2)
      if [ ! -f /etc/apt/sources.list.d/$repo_name.list ]; then
        echo "deb $repo $distro_version $repo_version"> /etc/apt/sources.list.d/$repo_name.list
        curl -sSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$key" | apt-key add -
      fi
      _ubuntu_repo_sync
    fi

    _ubuntu_install "$package"
  done < $DIR/ubuntu.csv
}

_main() {
  _detect_package_tool
  if [[ $(id -u) -ne 0 ]] && [ "$DISTRO" != "Arch Linux" ]; then
    sudo bash $0
    exit
  fi

  case $DISTRO in
    "Gentoo")
      _gentoo_init && _gentoo_run
      ;;
    "Arch Linux")
      _arch_init && _arch_run
      ;;
    "Ubuntu")
      _ubuntu_init && _ubuntu_run
      ;;
  esac
}

_main
