#!/bin/bash
set -Eeou pipefail

SETUP_DIR=$(dirname "$(readlink -f "$0")")
source "$SETUP_DIR/scripts/message.sh"

BIN_DIR="$HOME/.local/bin"
DEBUG="${1:-false}"

_install_chezmoi() {
  if [ ! "$(command -v chezmoi)" ]; then
    _notice "Install chezmoi"
    if command -v termux-setup-storage &> /dev/null; then
      pkg install -y chezmoi
      return
    fi

    if [ "$(command -v curl)" ]; then
      sh -c "$(curl -fsSL https://git.io/chezmoi)" -- -b "$BIN_DIR"
    elif [ "$(command -v wget)" ]; then
      sh -c "$(wget -qO- https://git.io/chezmoi)" -- -b "$BIN_DIR"
    else
      _error "To install chezmoi, you must have curl or wget installed."
    fi
  fi
}

_install_age() {
  if [ ! "$(command -v age)" ]; then
    _notice "Install age"
    if command -v termux-setup-storage &> /dev/null; then
      pkg install -y age
      return
    fi

    temp=$(mktemp)
    if [ "$(command -v curl)" ]; then
      curl -sSL -o "$temp" https://dl.filippo.io/age/latest?for=linux/amd64
    elif [ "$(command -v wget)" ]; then
      wget -qO "$temp" https://dl.filippo.io/age/latest?for=linux/amd64
    else
      _error "To install age, you must have curl or wget installed."
    fi

    if [ "$(command -v tar)" ]; then
      tar -C "$BIN_DIR" -xzf "$temp" --strip=1 age/age
    else
      _error "To install age, you must have tar and gzip installed."
    fi
    rm -rf "$temp"
  fi
}

_main() {
  # Install chezmoi and age
  mkdir -p "$BIN_DIR"
  export PATH="$BIN_DIR":"$PATH"
  _install_chezmoi

  # Run chezmoi in debug mode
  chezmoi_params=""
  if [ "$DEBUG" = "true" ]; then
    chezmoi_params="$chezmoi_params --debug"
  fi

  # Modify source directory of chezmoi, manipulate chezmoi config and generate
  # to chezmoi's default config template
  _notice "Initialize chezmoi"
  echo "sourceDir: \"$SETUP_DIR\"" > "$SETUP_DIR"/home/.chezmoi.yaml.tmpl
  cat "$SETUP_DIR"/.chezmoi.yaml.tmpl >> "$SETUP_DIR"/home/.chezmoi.yaml.tmpl
  mkdir -p "$HOME/.config/chezmoi/hooks/diff" && touch "$HOME/.config/chezmoi/hooks/diff/pre.sh"
  _notice "Please answer the following questions"
  # shellcheck disable=SC2086
  chezmoi init $chezmoi_params -S "$SETUP_DIR" --prompt

  # Apply configuration by order
  _notice "Setup SSH"
  _install_age
  # shellcheck disable=SC2086
  chezmoi apply $chezmoi_params $HOME/.ssh
  _notice "Setup other dotfiles"
  # shellcheck disable=SC2086
  chezmoi apply $chezmoi_params

  if ! command -v termux-setup-storage &> /dev/null;
    and ! command -v sw_vers &> /dev/null; then
    _notice "Setup operating system"
    yq '.mode = "file"' "$HOME/.config/chezmoi/chezmoi.yaml" > "$HOME/.config/chezmoi/root_chezmoi.yaml"
    sudo env "PATH=$PATH" \
      chezmoi \
      --destination / \
      --source "$SETUP_DIR/root" \
      --working-tree "$SETUP_DIR" \
      --config "$HOME/.config/chezmoi/root_chezmoi.yaml" \
      apply
  fi

  # Modify remote url of dotfiles
  _notice "Setup remote url of dotfiles"
  git remote set-url origin git@gitlab.com:dynamo-config/dotfiles
  git remote add gh git@github.com:dynamotn/dotfiles.git || git remote set-url gh git@github.com:dynamotn/dotfiles.git
  git config --local include.path ../.gitconfig

  _success "Setup complete"
}

if [ "$DEBUG" = "true" ]; then
  set -x
fi
_main
