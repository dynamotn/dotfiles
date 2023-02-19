#!/bin/sh
set -e

SETUP_DIR=$(dirname "$(readlink -f "$0")")
BIN_DIR="$HOME/.local/bin"

_install_chezmoi() {
  if [ ! "$(command -v chezmoi)" ]; then
    if [ "$(command -v curl)" ]; then
      sh -c "$(curl -fsSL https://git.io/chezmoi)" -- -b "$BIN_DIR"
    elif [ "$(command -v wget)" ]; then
      sh -c "$(wget -qO- https://git.io/chezmoi)" -- -b "$BIN_DIR"
    else
      echo "To install chezmoi, you must have curl or wget installed." >&2
      exit 1
    fi
  fi
}

_main() {
  _install_chezmoi

  export PATH="$BIN_DIR":"$PATH"
  chezmoi init -S "$SETUP_DIR" && chezmoi apply
}

_main
