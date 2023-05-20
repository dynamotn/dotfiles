#!/usr/bin/env bash

tar xzf $TEMP -C $BIN_DIR rbw
tar xzf $TEMP -C $BIN_DIR rbw-agent
if [ -d ~/.config/fish/completions ]; then
  $BIN_DIR/rbw gen-completions fish > ~/.config/fish/completions/rbw.fish
fi
if [ -d ~/Working/personal/fish/caran/completions ]; then
  $BIN_DIR/rbw gen-completions fish > ~/Working/personal/fish/caran/completions/rbw.fish
fi
