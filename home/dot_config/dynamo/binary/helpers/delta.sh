#!/bin/sh
tar xzf "$TEMP" --strip=1 -C "$BIN_DIR" delta-"${VERSION}"-x86_64-unknown-linux-gnu/delta
