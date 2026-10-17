#!/bin/sh
# dyshellint disable=BSG030,BSG031,BSG001,SC2292 POSIX sh bootstrap: it installs bash, so cannot need it or dybatpho
# @file prerequisite.sh
# @brief Install prerequisite packages for chezmoi and dotfiles setup
# @description Install what `scripts/setup.sh` cannot install itself: the
# package manager of the distribution, Git, curl, OpenSSH, Bash and the GNU
# tools the templates expect.
#
# It runs on a bare machine, often as `curl ... | sh`, where Bash may not be
# installed yet (Alpine and other minimal images ship only BusyBox `sh`). So it
# is written for POSIX `sh` and is the one script in this repository that does
# not build on dybatpho, which needs Bash 4.3 or newer. `local` is the single
# extension it uses; every `sh` it targets (dash, BusyBox ash, bash) has it.
#
# Root needs no escalation, which is the usual case inside a container image
# without `sudo`; otherwise `sudo` is preferred over `doas`.
set -eu

#######################################
# @description Pick the command that runs a command as root, into `SUDO`:
# empty when already root, else `sudo` or `doas`
# @noargs
# @set SUDO Escalation command, empty when none is needed
#######################################
_detect_sudo() {
  SUDO=""
  local uid
  uid="$(id -u)"
  if [ "${uid}" -eq 0 ]; then
    return 0
  fi
  if command -v sudo > /dev/null 2>&1; then
    SUDO="sudo"
  elif command -v doas > /dev/null 2>&1; then
    SUDO="doas"
  else
    echo "Not root, and neither sudo nor doas is installed; run this as root" >&2
    exit 1
  fi
}

#######################################
# @description Run a command as root, through `SUDO` when it is set
# @arg $@ string Command and its arguments
#######################################
_as_root() {
  if [ -n "${SUDO}" ]; then
    # dyshellint disable=BSG035 installing system packages is the point of this script
    "${SUDO}" "$@"
  else
    "$@"
  fi
}

#######################################
# @description Keep the sudo timestamp alive while the script runs. Nothing
# to do as root or with doas, which has no timestamp to refresh.
# @noargs
#######################################
_keep_sudo_alive() {
  if [ "${SUDO}" != "sudo" ]; then
    return 0
  fi
  # dyshellint disable=BSG035 priming the sudo timestamp is the point of this function
  sudo -v
  local parent_pid="$$"
  (
    while true; do
      # dyshellint disable=BSG035 refreshing the sudo timestamp is the point of this loop
      sudo -n true
      sleep 60
      kill -0 "${parent_pid}" 2> /dev/null || exit
    done
  ) 2> /dev/null &
  local sudo_pid="$!"
  # The pid is expanded now, while the local holds it: the trap runs after
  # this function has returned. EXIT alone also covers an interrupt, which
  # still ends the script as it would without the keepalive.
  # shellcheck disable=SC2064
  trap "kill -9 ${sudo_pid} 2> /dev/null || true" EXIT
}

#######################################
# @description Setup Gentoo
# @noargs
#######################################
_setup_gentoo() {
  _keep_sudo_alive
  # Cloning code
  _as_root emerge -uDN dev-vcs/git net-misc/curl net-misc/openssh
  # Templating of chezmoi
  _as_root emerge -uDN app-portage/cpuid2cpuflags app-misc/resolve-march-native
}

#######################################
# @description Setup Arch Linux
# @noargs
#######################################
_setup_arch() {
  _keep_sudo_alive
  # Cloning code. One full upgrade with the install: `-Sy` alone refreshes the
  # database without upgrading, a partial upgrade Arch does not support.
  _as_root pacman -Syu --needed --noconfirm ca-certificates git curl openssh bash
}

#######################################
# @description Setup Ubuntu/Debian
# @noargs
#######################################
_setup_ubuntu_debian() {
  _keep_sudo_alive
  # `apt-get` is the interface meant for scripts; `apt` warns that its own is
  # not stable. Without a terminal, debconf must not stop to ask anything.
  _as_root env DEBIAN_FRONTEND=noninteractive apt-get update
  # Cloning code
  _as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates git curl openssh-client bash
}

#######################################
# @description Setup Fedora and the other dnf-based distributions
# @noargs
#######################################
_setup_dnf() {
  _keep_sudo_alive
  # Cloning code
  _as_root dnf install -y ca-certificates git curl openssh-clients bash
}

#######################################
# @description Setup Alpine Linux
# @noargs
#######################################
_setup_alpine() {
  _keep_sudo_alive
  _as_root apk update
  # GNU compatible tools
  _as_root apk add --no-cache ca-certificates coreutils grep bash
  # Cloning code
  _as_root apk add --no-cache git curl openssh
}

#######################################
# @description Setup Termux
# @noargs
#######################################
_setup_termux() {
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
_setup_macos() {
  _keep_sudo_alive
  local brew_prefix installer
  if [ -x /opt/homebrew/bin/brew ]; then
    brew_prefix="/opt/homebrew"
  elif [ -x /usr/local/bin/brew ]; then
    brew_prefix="/usr/local"
  elif command -v brew > /dev/null 2>&1; then
    brew_prefix="$(brew --prefix)"
  else
    echo "Homebrew not found. Installing Homebrew..."
    installer="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    /bin/bash -c "${installer}"
    if [ -x /opt/homebrew/bin/brew ]; then
      brew_prefix="/opt/homebrew"
    else
      brew_prefix="/usr/local"
    fi
  fi

  # Everything below runs Homebrew from PATH, so a missing brew or an
  # environment it cannot print stops here rather than as a stream of
  # `brew: command not found`. The environment is captured first: sourced
  # straight from the command, a failing `brew shellenv` read as empty.
  if [ ! -x "${brew_prefix}/bin/brew" ]; then
    echo "Homebrew is not at ${brew_prefix}/bin/brew; install it and run again" >&2
    exit 1
  fi
  local brew_env
  if ! brew_env="$("${brew_prefix}/bin/brew" shellenv)"; then
    echo "\`${brew_prefix}/bin/brew shellenv\` failed; repair Homebrew and run again" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  . /dev/stdin << EOF
${brew_env}
EOF
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
    gnubin_path="${gnubin_path}:${brew_prefix}/opt/${formula}/libexec/gnubin"
  done
  gnubin_path="${gnubin_path}:${brew_prefix}/opt/gnu-getopt/bin"
  gnubin_path="${gnubin_path}:${brew_prefix}/opt/grep/libexec/gnubin"
  if ! grep -qs 'libexec/gnubin' ~/.zprofile; then
    echo "export PATH=\"${gnubin_path}:\$PATH\"" >> ~/.zprofile
  fi
}

#######################################
# @description Install the prerequisites of the running operating system
# @noargs
#######################################
_main() {
  local kernel
  kernel="$(uname -s)"

  if [ -n "${TERMUX_VERSION:-}" ] || [ -d "/data/data/com.termux" ]; then
    # Termux on Android
    _setup_termux
  elif [ "${kernel}" = "Darwin" ]; then
    # macOS
    _detect_sudo
    _setup_macos
  elif [ "${kernel}" = "Linux" ]; then
    _detect_sudo
    # Gentoo
    if command -v emerge > /dev/null 2>&1; then
      _setup_gentoo
    # ArchLinux
    elif command -v pacman > /dev/null 2>&1; then
      _setup_arch
    # Ubuntu/Debian
    elif command -v apt-get > /dev/null 2>&1; then
      _setup_ubuntu_debian
    # Fedora, RHEL and their rebuilds
    elif command -v dnf > /dev/null 2>&1; then
      _setup_dnf
    # Alpine Linux
    elif command -v apk > /dev/null 2>&1; then
      _setup_alpine
    else
      echo "Your distro is not supported" >&2
      exit 1
    fi
  else
    echo "Your OS (${kernel}) is not supported" >&2
    exit 1
  fi
}

_main
