#!/bin/bash
set -Eeuo pipefail

if command -v sw_vers &> /dev/null; then
  # MacOS
  curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash - || :
  (
    echo
    # shellcheck disable=2016
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"'
  ) >> ~/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
  brew install bash coreutils findutils gnu-tar gnu-sed gawk gnutls gnu-indent gnu-getopt grep chezmoi age yq
  echo "export PATH=\"/opt/homebrew/bin:/opt/homebrew/opt/coreutils/libexec/gnubin:/opt/homebrew/opt/findutils/libexec/gnubin:/opt/homebrew/opt/gnu-tar/libexec/gnubin:/opt/homebrew/opt/gnu-sed/libexec/gnubin:/opt/homebrew/opt/gawk/libexec/gnubin:/opt/homebrew/opt/gnu-indent/libexec/gnubin:/opt/homebrew/opt/gnu-getopt/bin:/opt/homebrew/opt/grep/libexec/gnubin:$PATH\"" >> ~/.zprofile
elif command -v termux-setup-storage &> /dev/null; then
  # Termux
  pkg update && pkg upgrade -y
  termux-change-repo
  termux-setup-storage
  pkg update && pkg install -y git curl tsu chezmoi age which python termux-services termux-exec openssh proot
elif command -v apt &> /dev/null; then
  # Ubuntu/Debian
  sudo apt update && sudo apt install -y git curl gnupg openssh-client
elif command -v pacman &> /dev/null; then
  # ArchLinux
  sudo pacman -Sy git curl openssh
elif command -v emerge &> /dev/null; then
  # Gentoo
  sudo emerge -uDN dev-vcs/git net-misc/curl net-misc/openssh
else
  echo "Your OS/distro is not supported"
  exit 1
fi

git clone https://github.com/dynamotn/dotfiles ~/Dotfiles
