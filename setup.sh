#!/bin/sh
set -e

SETUP_DIR=$(dirname "$(readlink -f "$0")")
BIN_DIR="$HOME/.local/bin"
DEBUG="${1:-false}"

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
  mkdir -p "$BIN_DIR"
  export PATH="$BIN_DIR":"$PATH"
  _install_chezmoi

  local chezmoi_params=""
  if [ "$DEBUG" = "true" ]; then
    chezmoi_params="$chezmoi_params --debug"
  fi
  echo "sourceDir = \"$SETUP_DIR\"" > $SETUP_DIR/home/.chezmoi.toml.tmpl
  cat $SETUP_DIR/.chezmoi.toml.tmpl >> $SETUP_DIR/home/.chezmoi.toml.tmpl
  chezmoi init $chezmoi_params -S "$SETUP_DIR" && \
    chezmoi apply $chezmoi_params
}

if [ "$DEBUG" = "true" ]; then
  set -x
  _main
else
  _main >/dev/null 2>&1
fi
