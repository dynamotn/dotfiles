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
  pkg install -y tsu which file
  # Termux only tools
  pkg install -y termux-services termux-exec proot
  # Cloning code
  pkg install -y git curl openssh
  # Chezmoi tools
  pkg install -y chezmoi age yq
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
  # Homebrew (still needed for: brew shellenv env setup, brew tap for --HEAD installs)
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
  # Zerobrew (performance-optimized client for Homebrew formulas)
  if ! command -v zb &> /dev/null; then
    echo "zerobrew not found. Installing zerobrew..."
    curl -fsSL https://zerobrew.rs/install | bash
    (
      echo
      echo 'export PATH="$HOME/.local/bin:$PATH"'
    ) >> ~/.zprofile
    export PATH="$HOME/.local/bin:$PATH"
  fi
  # GNU compatible tools (via zerobrew for performance)
  zb install bash coreutils findutils gnu-tar gnu-sed gawk gnutls gnu-indent grep
  # Cloning code (via zerobrew)
  zb install git curl
  # Chezmoi tools (via zerobrew)
  zb install chezmoi age
  echo "export PATH=\"/opt/zerobrew/bin:/opt/zerobrew/opt/coreutils/libexec/gnubin:/opt/zerobrew/opt/findutils/libexec/gnubin:/opt/zerobrew/opt/gnu-tar/libexec/gnubin:/opt/zerobrew/opt/gnu-sed/libexec/gnubin:/opt/zerobrew/opt/gawk/libexec/gnubin:/opt/zerobrew/opt/gnu-indent/libexec/gnubin:/opt/zerobrew/opt/gnu-getopt/bin:/opt/zerobrew/opt/grep/libexec/gnubin:$PATH\"" >> ~/.zprofile
}

function _main {
  case "$(uname -o)" in
    Android)
      # Termux
      _setup_termux
      ;;
    Linux)
      # Gentoo
      if command -v emerge &>/dev/null; then
        _setup_gentoo
      # ArchLinux
      elif command -v pacman &>/dev/null; then
        _setup_arch
      # Ubuntu/Debian
      elif command -v apt &>/dev/null; then
        _setup_ubuntu_debian
      # Alpine Linux
      elif command -v apk &>/dev/null; then
        _setup_alpine
      else
        echo "Your distro is not supported"
        exit 1
      fi
      ;;
    Darwin)
      _setup_macos
      ;;
    *)
      echo "Your OS is not supported"
      exit 1
      ;;
  esac
}

_main
