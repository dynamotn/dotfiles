#!/bin/bash

tar xzf $TEMP --strip=1 -C $BIN_DIR fd-$VERSION-x86_64-unknown-linux-gnu/fd
tar xzf $TEMP --strip=1 -C $MAN_DIR/man1 fd-$VERSION-x86_64-unknown-linux-gnu/fd.1
if [ -d ~/.config/fish/completions ]; then
  tar xzf $TEMP --strip=2 -C ~/.config/fish/completions fd-$VERSION-x86_64-unknown-linux-gnu/autocomplete/fd.fish
fi
if [ -d ~/Working/personal/fish/caran/completions ]; then
  tar xzf $TEMP --strip=2 -C ~/Working/personal/fish/caran/completions fd-$VERSION-x86_64-unknown-linux-gnu/autocomplete/fd.fish
fi
