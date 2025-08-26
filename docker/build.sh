#!/usr/bin/env bash
# @file build.sh
# @brief Build container and setup dotfiles
set -Eeou pipefail
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")/../scripts"

#######################################
# @description Install custom SSL certificates if provided in Docker secrets.
#######################################
function _install_ssl_certs {
  if [ -f /run/secrets/ssl_cert ]; then
    folder=""
    if command -v apk &> /dev/null; then
      folder="/usr/local/share/ca-certificates"
      command="update-ca-certificates"
    elif command -v pacman &> /dev/null; then
      folder="/etc/ca-certificates/trust-source/anchors"
      command="update-ca-trust"
    fi

    sudo cp /run/secrets/ssl_cert "$folder/ssl_decryption.crt"
    sudo "$command"
  fi
}

#######################################
# @description Install packages required for setting up dotfiles.
#######################################
function _install_packages {
  if command -v pacman &> /dev/null; then
    # Choose mirror for VN
    echo "Server = http://mirror.bizflycloud.vn/archlinux/\$repo/os/\$arch" | sudo tee /etc/pacman.d/mirrorlist
    # Container only tools
    sudo pacman -Sy --noconfirm expect
    # Install for cloning code
    sudo pacman -Sy --noconfirm git curl openssh
    # Install chezmoi tools
    sudo pacman -Sy --noconfirm chezmoi age expect
  elif command -v apk &> /dev/null; then
    sudo apk update
    # Container only tools
    sudo apk add --no-cache expect
    # GNU compatible tools
    sudo apk add --no-cache coreutils grep file
    # Install for cloning code
    sudo apk add --no-cache git curl openssh
    # Install chezmoi tools
    sudo apk add --no-cache chezmoi age
  fi
}

#######################################
# @description Main function to setup dotfiles.
#######################################
function _main {
  _install_ssl_certs
  _install_packages

  # Disable SSH host key checking
  export GIT_SSH_COMMAND="ssh -oStrictHostKeyChecking=no"
  # Get identities from secrets
  if [ -f /run/secrets/age_passphrases ]; then
    local age_passphrases
    age_passphrases=$(sudo cat /run/secrets/age_passphrases)
    local identities=""
    for passphrase in $age_passphrases; do
      IFS='=' read -r key _ <<< "$passphrase"
      identities="${identities}${key},"
    done
  else
    exit 1
  fi

  # Setup dotfiles
  "$SCRIPT_DIR"/setup.sh -d -i"$identities"

  # Delete sensitive data
  rm -rf ~/.config/chezmoi/*.key ~/Dotfiles/secrets
  # Delete unnecessary data
  rm -rf ~/.cache/chezmoi ~/Dotfiles/.git*
  # Uninstall packages
  if command -v pacman &> /dev/null; then
    sudo pacman -Rnsc --noconfirm chezmoi
  elif command -v apk &> /dev/null; then
    sudo apk del chezmoi
  fi
}

_main
