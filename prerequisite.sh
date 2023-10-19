#!/bin/sh
set -Eeuo pipefail

if command -v termux-setup-storage &> /dev/null; then
  termux-change-repo
  termux-setup-storage
  pkg update && pkg install -y git curl which
  pkg install -y chezmoi age
elif command -v apt &> /dev/null; then
  sudo apt update && sudo apt install -y git curl
elif command -v pacman &> /dev/null; then
  sudo pacman -Sy git curl
elif command -v emerge &> /dev/null; then
  sudo emerge -uDN dev-vcs/git net-misc/curl
fi

git clone https://github.com/dynamotn/dotfiles ~/Dotfiles
