#!/bin/sh
set -eou pipefail

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

_install_age() {
  if [ ! "$(command -v age)" ]; then
    temp=$(mktemp)
    if [ "$(command -v curl)" ]; then
      curl -sSL -o "$temp" https://dl.filippo.io/age/latest?for=linux/amd64
    elif [ "$(command -v wget)" ]; then
      wget -qO "$temp" https://dl.filippo.io/age/latest?for=linux/amd64
    else
      echo "To install age, you must have curl or wget installed." >&2
      exit 1
    fi

    if [ "$(command -v tar)" ]; then
      tar -C "$BIN_DIR" -xzf "$temp" --strip=1 age/age
    else
      echo "To install age, you must have tar and gzip installed." >&2
    fi
    rm -rf "$temp"
  fi
}

_main() {
  # Install chezmoi and age
  mkdir -p "$BIN_DIR"
  export PATH="$BIN_DIR":"$PATH"
  _install_chezmoi
  _install_age

  # Run chezmoi in debug mode
  chezmoi_params=""
  if [ "$DEBUG" = "true" ]; then
    chezmoi_params="$chezmoi_params --debug"
  fi

  # Modify source directory of chezmoi, manipulate chezmoi config and generate
  # to chezmoi's default config template
  echo "sourceDir = \"$SETUP_DIR\"" > "$SETUP_DIR"/home/.chezmoi.toml.tmpl
  cat "$SETUP_DIR"/.chezmoi.toml.tmpl >> "$SETUP_DIR"/home/.chezmoi.toml.tmpl
  chezmoi init "$chezmoi_params" -S "$SETUP_DIR"

  # Apply configuration by order
  # shellcheck disable=SC2086
  chezmoi apply $chezmoi_params "$HOME/.ssh"
  # shellcheck disable=SC2086
  chezmoi apply $chezmoi_params
}

if [ "$DEBUG" = "true" ]; then
  set -x
  _main
else
  _main > /dev/null 2>&1
fi
