#!/bin/bash

SETUP_DIR=$(dirname "$(readlink -f "$0")")

_link() {
  if [[ -e "$2" || -L "$2" ]]; then
    if test "$1" -ef "$(readlink -f "$2")"; then
      echo "${2} linked"
      return
    else
      rm -rf "$2"
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
  $SETUP_DIR/fish/setup.fish
  _link "$SETUP_DIR/vim" ~/.config/nvim

  # Terminal application
  _link "$SETUP_DIR/tmux/config" ~/.tmux.conf
  _link "$SETUP_DIR/htop" ~/.config/htop
}

_install
git --work-tree=$SETUP_DIR submodule update --init --recursive --remote
