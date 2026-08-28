#!/bin/bash
# @file prerequisite.sh
# @brief Install prerequisite packages for chezmoi and dotfiles setup
set -Eeuo pipefail

#######################################
# @description Keep sudo alive
#######################################
function _keep_sudo_alive {
  if command -v sudo &>/dev/null; then
    sudo -v
    (
      while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" 2>/dev/null || exit
      done
    ) 2>/dev/null &
    local sudo_pid=$!
    trap 'kill -9 "$sudo_pid" 2>/dev/null || true' EXIT INT TERM
  fi
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
  sudo pacman -Sy --needed --noconfirm ca-certificates git curl openssh
}

#######################################
# @description Setup Ubuntu/Debian
#######################################
function _setup_ubuntu_debian {
  _keep_sudo_alive
  sudo apt update
  # Cloning code
  sudo apt install -y ca-certificates git curl openssh-client
}

#######################################
# @description Setup Alpine Linux
#######################################
function _setup_alpine {
  _keep_sudo_alive
  sudo apk update
  # GNU compatible tools
  sudo apk add --no-cache ca-certificates coreutils grep bash
  # Cloning code
  sudo apk add --no-cache git curl openssh
}

#######################################
# @description Setup Termux
#######################################
function _setup_termux {
  pkg update -y && pkg upgrade -y
  termux-change-repo && pkg update -y
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
  local brew_prefix
  if [[ -x /opt/homebrew/bin/brew ]]; then
    brew_prefix="/opt/homebrew"
  elif [[ -x /usr/local/bin/brew ]]; then
    brew_prefix="/usr/local"
  elif command -v brew &>/dev/null; then
    brew_prefix="$(brew --prefix)"
  else
    echo "Homebrew not found. Installing Homebrew..."
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then
      brew_prefix="/opt/homebrew"
    else
      brew_prefix="/usr/local"
    fi
  fi

  if [[ -x "${brew_prefix}/bin/brew" ]]; then
    eval "$("${brew_prefix}/bin/brew" shellenv)"
    if ! grep -qs 'brew shellenv' ~/.zprofile; then
      echo "eval \"\$(${brew_prefix}/bin/brew shellenv)\"" >> ~/.zprofile
    fi
  fi

  # GNU compatible tools
  brew install bash coreutils findutils gnu-tar gnu-sed gawk gnutls gnu-indent grep
  # Cloning code & chezmoi tools
  brew install git curl openssh chezmoi age yq

  local gnubin_path="${brew_prefix}/bin:${brew_prefix}/opt/coreutils/libexec/gnubin:${brew_prefix}/opt/findutils/libexec/gnubin:${brew_prefix}/opt/gnu-tar/libexec/gnubin:${brew_prefix}/opt/gnu-sed/libexec/gnubin:${brew_prefix}/opt/gawk/libexec/gnubin:${brew_prefix}/opt/gnu-indent/libexec/gnubin:${brew_prefix}/opt/gnu-getopt/bin:${brew_prefix}/opt/grep/libexec/gnubin"
  if ! grep -qs 'libexec/gnubin' ~/.zprofile; then
    echo "export PATH=\"${gnubin_path}:\$PATH\"" >> ~/.zprofile
  fi
}

function _main {
  local kernel
  kernel="$(uname -s)"

  if [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d "/data/data/com.termux" ]]; then
    # Termux on Android
    _setup_termux
  elif [[ "$kernel" == "Darwin" ]]; then
    # macOS
    _setup_macos
  elif [[ "$kernel" == "Linux" ]]; then
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
  else
    echo "Your OS ($kernel) is not supported"
    exit 1
  fi
}

_main
