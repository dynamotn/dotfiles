#!/bin/sh
set -Eeuo pipefail

if command -v sw_vers &> /dev/null; then
  curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash - || :
  (echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> ~/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
  brew install bash coreutils findutils gnu-tar gnu-sed gawk gnutls gnu-indent gnu-getopt grep chezmoi age yq
  echo "export PATH=\"/opt/homebrew/bin:/opt/homebrew/opt/coreutils/libexec/gnubin:/opt/homebrew/opt/findutils/libexec/gnubin:/opt/homebrew/opt/gnu-tar/libexec/gnubin:/opt/homebrew/opt/gnu-sed/libexec/gnubin:/opt/homebrew/opt/gawk/libexec/gnubin:/opt/homebrew/opt/gnu-indent/libexec/gnubin:/opt/homebrew/opt/gnu-getopt/bin:/opt/homebrew/opt/grep/libexec/gnubin:$PATH\"" >> ~/.zprofile
elif command -v termux-setup-storage &> /dev/null; then
  termux-change-repo
  termux-setup-storage
  pkg update && pkg install -y git curl tsu
  pkg install -y chezmoi age
elif command -v apt &> /dev/null; then
  sudo apt update && sudo apt install -y git curl gnupg
elif command -v pacman &> /dev/null; then
  sudo pacman -Sy git curl
elif command -v emerge &> /dev/null; then
  sudo emerge -uDN dev-vcs/git net-misc/curl
fi

git clone https://github.com/dynamotn/dotfiles ~/Dotfiles
