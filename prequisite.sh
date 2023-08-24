#!/bin/sh
set -Eeuo pipefail

if command -v termux-setup-storage &> /dev/null; then
  termux-change-repo
  termux-setup-storage
  pkg update && pkg install -y git curl tar gzip openssh neovim which
  pkg install -y chezmoi age
elif command -v apt &> /dev/null; then
  apt update && apt install -y git curl tar gzip openssh neovim
elif command -v pacman &> /dev/null; then
  pacman -Sy git curl tar gzip neovim
elif command -v emerge &> /dev/null; then
  emerge -uDN dev-vcs-git net-misc/curl app-arch/tar app-arch/gzip net-misc/openssh app-editors/neovim
fi

git clone https://github.com/dynamotn/dotfiles Dotfiles
