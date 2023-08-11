#!/bin/bash

tar xzf $TEMP --strip=1 -C $BIN_DIR bat-$VERSION-x86_64-unknown-linux-gnu/bat
tar xzf $TEMP --strip=1 -C $MAN_DIR/man1 bat-$VERSION-x86_64-unknown-linux-gnu/bat.1
if [ -d ~/.config/fish/completions ]; then
  tar xzf $TEMP --strip=2 -C ~/.config/fish/completions bat-$VERSION-x86_64-unknown-linux-gnu/autocomplete/bat.fish
fi
if [ -d ~/Working/personal/fish/caran/completions ]; then
  tar xzf $TEMP --strip=2 -C ~/Working/personal/fish/caran/completions bat-$VERSION-x86_64-unknown-linux-gnu/autocomplete/bat.fish
fi
