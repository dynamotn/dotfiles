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
    if [[ -d $1 && $HOME != "$(dirname "$2")" && ! -d "$(dirname "$2")" ]]; then
      rm -rf "$(dirname "$2")"
    fi
  fi
  mkdir -p "$(dirname "$2")"
  ln -sv "$1" "$2"
}

_install() {
  # Basic UI
  _link "$SETUP_DIR/X/resources" ~/.Xresources
  _link "$SETUP_DIR/X/font/files" ~/.local/share/fonts
  _link "$SETUP_DIR/X/theme/gtk" ~/.themes
  _link "$SETUP_DIR/X/theme/icon-cursor" ~/.icons
  _link "$SETUP_DIR/gtk/2/rc" ~/.gtkrc-2.0
  _link "$SETUP_DIR/gtk/3/settings.ini" ~/.config/gtk-3.0/settings.ini
  _link "$SETUP_DIR/qt/config" ~/.config/Trolltech.conf

  # Basic service
  _link "$SETUP_DIR/git" ~/.git
  _link "$SETUP_DIR/git/config" ~/.gitconfig

  # Become a hacker
  _link "$SETUP_DIR/kitty/config" ~/.config/kitty/kitty.conf
  _link "$SETUP_DIR/fish" ~/.config/fish # Must setup fish shell before vim
  if ! $LINK_ONLY; then
    $SETUP_DIR/fish/setup.fish
  fi
  _link "$SETUP_DIR/vim" ~/.config/nvim

  # Terminal application
  _link "$SETUP_DIR/tmux/config" ~/.tmux.conf
  _link "$SETUP_DIR/htop" ~/.config/htop
  _link "$SETUP_DIR/bat" ~/.config/bat

  # WM and compositor
  _link "$SETUP_DIR/awesome" ~/.config/awesome
  _link "$SETUP_DIR/compton/config" ~/.config/compton.conf

  # Multimedia
  _link "$SETUP_DIR/mpd/config" ~/.config/mpd/mpd.conf
  mkdir -p ~/.config/mpd/playlists
  _link "$SETUP_DIR/ncmpcpp" ~/.ncmpcpp

  # X11 miscelaneous
  _link "$SETUP_DIR/redshift/config" ~/.config/redshift/redshift.conf
  _link "$SETUP_DIR/copyq/config" ~/.config/copyq/copyq.conf
  _link "$SETUP_DIR/X/xdg/user-dirs.dirs" ~/.config/user-dirs.dirs
  _link "$SETUP_DIR/X/profile" ~/.xprofile
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
