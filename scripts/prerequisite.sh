#!/bin/bash
# dyshellint disable=BSG030
# @file prerequisite.sh
# @brief Install prerequisite packages for chezmoi and dotfiles setup
# @description Install what `scripts/setup.sh` cannot install itself: the
# package manager of the distribution, Git, curl, OpenSSH and the GNU tools the
# templates expect. It runs on a bare machine, so it uses nothing but Bash and
# the system package manager, and never sources dybatpho.
set -euo pipefail

#######################################
# @description Keep sudo alive
# @noargs
#######################################
function _keep_sudo_alive {
  if command -v sudo &> /dev/null; then
    # dyshellint disable=BSG035 priming the sudo timestamp is the point of this function
    sudo -v
    (
      while true; do
        # dyshellint disable=BSG035 refreshing the sudo timestamp is the point of this loop
        sudo -n true
        sleep 60
        kill -0 "$$" 2> /dev/null || exit
      done
    ) 2> /dev/null &
    local sudo_pid=$!
    # The pid is expanded now, while the local holds it: the trap runs after
    # this function has returned. EXIT alone also covers an interrupt, which
    # still ends the script as it would without the keepalive.
    # shellcheck disable=SC2064
    trap "kill -9 ${sudo_pid} 2> /dev/null || true" EXIT
  fi
}

#######################################
# @description Setup Gentoo
# @noargs
#######################################
function _setup_gentoo {
  _keep_sudo_alive
  # Cloning code
  # dyshellint disable=BSG035 emerge writes to the system Portage tree
  sudo emerge -uDN dev-vcs/git net-misc/curl net-misc/openssh
  # Templating of chezmoi
  # dyshellint disable=BSG035 emerge writes to the system Portage tree
  sudo emerge -uDN app-portage/cpuid2cpuflags app-misc/resolve-march-native
}

#######################################
# @description Setup Arch Linux
# @noargs
#######################################
function _setup_arch {
  _keep_sudo_alive
  # Cloning code
  # dyshellint disable=BSG035 pacman writes to the system package database
  sudo pacman -Sy --needed --noconfirm ca-certificates git curl openssh
}

#######################################
# @description Setup Ubuntu/Debian
# @noargs
#######################################
function _setup_ubuntu_debian {
  _keep_sudo_alive
  # dyshellint disable=BSG035 apt writes to the system package database
  sudo apt update
  # Cloning code
  # dyshellint disable=BSG035 apt writes to the system package database
  sudo apt install -y ca-certificates git curl openssh-client
}

#######################################
# @description Setup Alpine Linux
# @noargs
#######################################
function _setup_alpine {
  _keep_sudo_alive
  # dyshellint disable=BSG035 apk writes to the system package database
  sudo apk update
  # GNU compatible tools
  # dyshellint disable=BSG035 apk writes to the system package database
  sudo apk add --no-cache ca-certificates coreutils grep bash
  # Cloning code
  # dyshellint disable=BSG035 apk writes to the system package database
  sudo apk add --no-cache git curl openssh
}

#######################################
# @description Setup Termux
# @noargs
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
# @noargs
#######################################
function _setup_macos {
  _keep_sudo_alive
  local brew_prefix
  if [[ -x /opt/homebrew/bin/brew ]]; then
    brew_prefix="/opt/homebrew"
  elif [[ -x /usr/local/bin/brew ]]; then
    brew_prefix="/usr/local"
  elif command -v brew &> /dev/null; then
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

  # Everything below runs Homebrew from PATH, so a missing brew or an
  # environment it cannot print stops here rather than as a stream of
  # `brew: command not found`. The environment is captured first: sourced
  # through a process substitution, a failing `brew shellenv` read as empty.
  if [[ ! -x "${brew_prefix}/bin/brew" ]]; then
    echo "Homebrew is not at ${brew_prefix}/bin/brew; install it and run again" >&2
    exit 1
  fi
  local brew_env
  if ! brew_env="$("${brew_prefix}/bin/brew" shellenv)"; then
    echo "\`${brew_prefix}/bin/brew shellenv\` failed; repair Homebrew and run again" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  . /dev/stdin <<< "${brew_env}"
  if ! grep -qs 'brew shellenv' ~/.zprofile; then
    echo "eval \"\$(${brew_prefix}/bin/brew shellenv)\"" >> ~/.zprofile
  fi

  # GNU compatible tools
  brew install bash coreutils findutils gnu-tar gnu-sed gawk gnutls gnu-indent grep
  # Cloning code & chezmoi tools
  brew install git curl openssh chezmoi age yq

  local gnubin_path="${brew_prefix}/bin"
  local formula
  for formula in coreutils findutils gnu-tar gnu-sed gawk gnu-indent; do
    gnubin_path+=":${brew_prefix}/opt/${formula}/libexec/gnubin"
  done
  gnubin_path+=":${brew_prefix}/opt/gnu-getopt/bin"
  gnubin_path+=":${brew_prefix}/opt/grep/libexec/gnubin"
  if ! grep -qs 'libexec/gnubin' ~/.zprofile; then
    echo "export PATH=\"${gnubin_path}:\$PATH\"" >> ~/.zprofile
  fi
}

#######################################
# @description Install the prerequisites of the running operating system
# @noargs
#######################################
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
    else
      echo "Your distro is not supported" >&2
      exit 1
    fi
  else
    echo "Your OS ($kernel) is not supported" >&2
    exit 1
  fi
}

_main
