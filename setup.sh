#!/bin/bash

SETUP_DIR=$(dirname "$(readlink -f "$0")")
LINK_ONLY=false

_usage() {
  echo "$0 usage:" && grep " .)\\ #" $0 | sed -e 's/\(.\)) #/-\1/g'
  exit 0;
}

_link() {
  if [[ -e "$2" || -L "$2" ]]; then
    if test "$1" -ef "$(readlink -f "$2")"; then
      echo "${2} linked"
      return
    else
      rm -rf "$2"
    fi
  else
    if [[ -d $1 && $HOME != "$(dirname "$2")" ]]; then
      rm -rf "$(dirname "$2")"
    fi
  fi
  mkdir -p "$(dirname "$2")"
  ln -sv "$1" "$2"
}

_install() {
  # Basic service
  _link "$SETUP_DIR/git" ~/.git
  _link "$SETUP_DIR/git/config" ~/.gitconfig

  # Become a hacker
  _link "$SETUP_DIR/fish" ~/.config/fish # Must setup fish shell before vim
  if ! $LINK_ONLY; then
    $SETUP_DIR/fish/setup.fish
  fi
  _link "$SETUP_DIR/vim" ~/.config/nvim

  # Terminal application
  _link "$SETUP_DIR/tmux/config" ~/.tmux.conf
  _link "$SETUP_DIR/htop" ~/.config/htop
  _link "$SETUP_DIR/bat" ~/.config/bat
}

while getopts "hls" arg; do
  case $arg in
    s) # Update git submodule before setup
      git --work-tree=$SETUP_DIR submodule update --init --recursive --remote
      ;;
    l) # Create link only
      LINK_ONLY=true
      ;;
    h) # Display help
      _usage
      ;;
  esac
done

_install
