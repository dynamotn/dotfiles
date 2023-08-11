#!/bin/bash

unzip -qqoj $TEMP bin/exa -d $BIN_DIR
unzip -qqoj $TEMP man/*.1 -d $MAN_DIR/man1
unzip -qqoj $TEMP man/*.5 -d $MAN_DIR/man5
if [ -d ~/.config/fish/completions ]; then
  unzip -qqoj $TEMP completions/exa.fish -d ~/.config/fish/completions
fi
if [ -d ~/Working/personal/fish/caran/completions ]; then
  unzip -qqoj $TEMP completions/exa.fish -d ~/Working/personal/fish/caran/completions
fi
