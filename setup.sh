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

  # Basic UI
  _link "$SETUP_DIR/X/resources" ~/.Xresources
  _link "$SETUP_DIR/X/font/files" ~/.local/share/fonts
  _link "$SETUP_DIR/X/font/config" ~/.config/fontconfig/conf.d
  _link "$SETUP_DIR/X/theme/gtk" ~/.local/share/themes
  _link "$SETUP_DIR/X/theme/icon-cursor" ~/.local/share/icons
  _link "$SETUP_DIR/gtk/2/rc" ~/.gtkrc-2.0
  _link "$SETUP_DIR/gtk/3/settings.ini" ~/.config/gtk-3.0/settings.ini
  _link "$SETUP_DIR/qt/config" ~/.config/Trolltech.conf

  # Basic service
  _link "$SETUP_DIR/git" ~/.git
  _link "$SETUP_DIR/git/config" ~/.gitconfig

  # Become a hacker
  _link "$SETUP_DIR/kitty" ~/.config/kitty
  _link "$SETUP_DIR/kitty/config" ~/.config/kitty/kitty.conf
  _link "$SETUP_DIR/fish" ~/.config/fish # Must setup fish shell before vim
  ! $LINK_ONLY && chsh -s $(which fish) && $SETUP_DIR/fish/setup.fish
  _link "$SETUP_DIR/vim" ~/.config/nvim
  ! $LINK_ONLY && command -v nvim > /dev/null 2>&1 && nvim +PlugInstall +UpdateRemotePlugins +qa
  ! $LINK_ONLY && bash $SETUP_DIR/bin/update.sh -n

  # Terminal application
  _link "$SETUP_DIR/tmux/config" ~/.tmux.conf
  _link "$SETUP_DIR/htop" ~/.config/htop
  _link "$SETUP_DIR/bat" ~/.config/bat

  # WM and compositor
  _link "$SETUP_DIR/awesome" ~/.config/awesome
  _link "$SETUP_DIR/picom/config" ~/.config/picom/picom.conf

  # Multimedia
  _link "$SETUP_DIR/mpd/config" ~/.config/mpd/mpd.conf
  _create ~/.config/mpd/playlists
  _link "$SETUP_DIR/ncmpcpp" ~/.ncmpcpp

  # X11 miscelaneous
  _link "$SETUP_DIR/redshift/config" ~/.config/redshift/redshift.conf
  _link "$SETUP_DIR/copyq/config" ~/.config/copyq/copyq.conf
  _link "$SETUP_DIR/X/xdg/user-dirs.dirs" ~/.config/user-dirs.dirs
  _link "$SETUP_DIR/X/profile" ~/.xprofile
  _link "$SETUP_DIR/ibus/bamboo/config.json" ~/.config/ibus-bamboo/ibus-bamboo.config.json
  if command -v dconf > /dev/null 2>&1; then
    dconf load / < "$SETUP_DIR/dconf/config"
    echo "Loaded dconf"
  fi

  # GUI application
  ! $LINK_ONLY && $SETUP_DIR/firefox/setup.sh
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
