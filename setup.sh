#!/bin/bash

SETUP_DIR=$(dirname "$(readlink -f "$0")")
LINK_ONLY=false
INSTALL_PACKAGE=

# Show usage
_usage() {
  echo "$0 usage:" && grep " .)\\ #" $0 | sed -e 's/\(.\)) #/-\1/g'
  exit 0;
}

# Create symbolic link for config
# $1: The source of symlink
# $2: The destination of symlink
# $3: When true, create parent directories to the link as needed. (default: true)
# $4: Force removes the old destination, file or folder, and forces a new link (default: true)
_link() {
  local need_create_parent=${3:-true}
  local is_force=${4:-true}

  if [[ -e "$2" || -L "$2" ]]; then
  # Check destination is existed or is a symlink
    if test "$1" -ef "$(readlink -f "$2")"; then
    # If symlink is setup same with source then finish
      echo "${2} linked"
      return
    else
    # Delete destination if not a symlink or target of symlink is not same with source
      [ "$is_force" = true ] && rm -rf "$2"
    fi
  fi
  [ "$need_create_parent" = true ] && mkdir -p "$(dirname "$2")"
  ln -sv "$1" "$2"
}

# Create empty folder
_create() {
  mkdir -p "$*"
}

_install() {
  ! $LINK_ONLY && $SETUP_DIR/distros/install_linux_package.sh

  # Basic service
  _link "$SETUP_DIR/git" ~/.git
  _link "$SETUP_DIR/git/config" ~/.gitconfig

  # Become a hacker
  _link "$SETUP_DIR/fish" ~/.config/fish # Must setup fish shell before vim
  ! $LINK_ONLY && chsh -s $(which fish) && $SETUP_DIR/fish/setup.fish
  _link "$SETUP_DIR/vim" ~/.config/nvim
  _link "$SETUP_DIR/vim" ~/.vim
  _link "$SETUP_DIR/vim/vimrc" ~/.vimrc
  if ! $LINK_ONLY; then
    if command -v nvim > /dev/null 2>&1; then
      nvim +PlugInstall +UpdateRemotePlugins +qa
    elif command -v vim > /dev/null 2>&1; then
      vim +PlugInstall +qa
    fi
  fi
  ! $LINK_ONLY && bash $SETUP_DIR/bin/update.sh -n

  # Terminal application
  _link "$SETUP_DIR/tmux/config" ~/.tmux.conf
  _link "$SETUP_DIR/htop" ~/.config/htop
  _link "$SETUP_DIR/bat" ~/.config/bat
}

while getopts "hlsp" arg; do
  case $arg in
    s) # Update git submodule before setup
      git -C $SETUP_DIR submodule update --init --recursive --remote
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
