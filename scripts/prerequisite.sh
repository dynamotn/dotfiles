#!/bin/bash
# @file prerequisite.sh
# @brief Install prerequisite packages for chezmoi and dotfiles setup
set -Eeuo pipefail

#######################################
# @description Keep sudo alive
#######################################
function _keep_sudo_alive {
  sudo -v
  while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" || exit
  done 2> /dev/null &
}

#######################################
# @description Setup Gentoo
#######################################
function _setup_gentoo {
  _keep_sudo_alive
  # Cloning code
  sudo emerge -uDN dev-vcs/git net-misc/curl net-misc/openssh
  # Templating of chezmoi
  sudo emerge -uDN app-portage/cpuid2cpuflags app-misc/resolve-march-native
}

#######################################
# @description Setup Arch Linux
#######################################
function _setup_arch {
  _keep_sudo_alive
  # Cloning code
  sudo pacman -Sy --noconfirm git curl openssh
}

#######################################
# @description Setup Ubuntu/Debian
#######################################
function _setup_ubuntu_debian {
  _keep_sudo_alive
  sudo apt update
  # Cloning code
  sudo apt install -y git curl openssh-client
}

#######################################
# @description Setup Alpine Linux
#######################################
function _setup_alpine {
  _keep_sudo_alive
  sudo apk update
  # GNU compatible tools
  sudo apk add --no-cache coreutils grep
  # Cloning code
  sudo apk add --no-cache git curl openssh
}

#######################################
# @description Setup Termux
#######################################
function _setup_termux {
  pkg update && pkg upgrade -y
  termux-change-repo && pkg update
  termux-setup-storage
  # Linux compatible tools
  pkg install -y tsu which
  # Termux only tools
  pkg install -y termux-services tmux-exec proot
  # Cloning code
  pkg install -y git curl openssh
  # Chezmoi tools
  pkg install -y chezmoi age
  # F-Droid tools
  pkg install -y fdroidcl
  # Turn on Android Settings, setting Wireless debugging manually
  am start -a android.settings.SETTINGS
  # NOTE: use adb to pair & connect localhost Wireless debugging
}

#######################################
# @description Setup MacOS
#######################################
function _setup_macos {
  _keep_sudo_alive
  # Homebrew
  if ! command -v brew &> /dev/null; then
    echo "Homebrew not found. Installing Homebrew..."
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    (
      echo
      # shellcheck disable=2016
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"'
    ) >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  # GNU compatible tools
  brew install bash coreutils findutils gnu-tar gnu-sed gawk gnutls gnu-indent grep
  # Cloning code
  brew install git curl
  # Chezmoi tools
  brew install chezmoi age
  echo "export PATH=\"/opt/homebrew/bin:/opt/homebrew/opt/coreutils/libexec/gnubin:/opt/homebrew/opt/findutils/libexec/gnubin:/opt/homebrew/opt/gnu-tar/libexec/gnubin:/opt/homebrew/opt/gnu-sed/libexec/gnubin:/opt/homebrew/opt/gawk/libexec/gnubin:/opt/homebrew/opt/gnu-indent/libexec/gnubin:/opt/homebrew/opt/gnu-getopt/bin:/opt/homebrew/opt/grep/libexec/gnubin:$PATH\"" >> ~/.zprofile
}

function _main {
  # Gentoo
  if command -v emerge &> /dev/null; then
    _setup_gentoo
  # ArchLinux
  elif command -v pacman &> /dev/null; then
    _setup_arch
  # Ubuntu/Debian
  elif command -v apt &> /dev/null; then
    _setup_ubuntu_debian
  # Alpine Linux
  elif command -v apk &> /dev/null; then
    _setup_alpine
  # Termux
  elif command -v termux-setup-storage &> /dev/null; then
    _setup_termux
  # MacOS
  elif command -v sw_vers &> /dev/null; then
    _setup_macos
  else
    echo "Your OS/distro is not supported"
    exit 1
  fi
  if ! [ -d ~/Dotfiles ]; then
    git clone https://github.com/dynamotn/dotfiles ~/Dotfiles
  fi
  bash ~/Dotfiles/scripts/setup.sh
}

_main
