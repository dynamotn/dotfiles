#!/bin/bash

_gentoo_repo_sync() {
  sudo emerge --sync
}

_gentoo_install() {
  if [ ! -x '/usr/bin/qlist' ]; then
    echo >&2 ":: Error: Must install app-portage/portage-utils first."
  fi
  qlist -I "$1" > /dev/null || sudo emerge --ask n --noreplace "$1"
}

_gentoo_init() {
  _gentoo_repo_sync
  _gentoo_install app-portage/gentoolkit
  _gentoo_install app-portage/portage-utils
  _gentoo_install app-eselect/eselect-repository
  sudo eselect repository add dynamo git https://github.com/dynamotn/overlay.git
}

_arch_repo_sync() {
  if ! command -v yay > /dev/null; then
    sudo pacman -Sy
  else
    yay -Sy
  fi
}

_arch_install() {
  pacman -Qi "$1" > /dev/null || yay --noconfirm -S --needed --answerclean All --answerdiff None "$1"
}

_arch_init() {
  _arch_repo_sync
  if ! command -v yay > /dev/null; then
    sudo pacman -S --needed git base-devel go
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay || exit
    makepkg -si --noconfirm
    rm -rf /tmp/yay
    sudo pacman -Rscn --noconfirm go
  fi
}

_ubuntu_repo_sync() {
  sudo apt update
}

_ubuntu_install() {
  dpkg-query -s "$1" > /dev/null 2>&1 || sudo apt install -y "$1"
}

_ubuntu_init() {
  _ubuntu_repo_sync
}

_termux_repo_sync() {
  pkg update
}

_termux_init() {
  _termux_repo_sync
}

_termux_install() {
  dpkg-query -s "$1" > /dev/null 2>&1 || pkg install -y "$1"
}

_macos_init() {
  brew install mas
}

_macos_install() {
  brew ls | grep -E "^$1$" || (
    if [ -z "$3" ]; then
      brew install "$2" "$1"
    else
      brew install "$2" "$1" "$3"
    fi
  )
}
