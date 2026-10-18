#!/usr/bin/env fish
# Install fisher and bring the plugins in line with `plugins.list`.
#
# `plugins.list` is the source of truth: it overwrites `fish_plugins`, so a
# plugin dropped from the list is also removed by `fisher update`.
#
# Usage: setup.fish [-u | --update]
#   -u, --update  reinstall fisher even when it is already installed

argparse u/update -- $argv; or exit 1

# Not the directory of this script: chezmoi links it back into the source
# tree, while `plugins.list` is rendered from a template into the real one.
set -l plugins_list $__fish_config_dir/plugins.list
set -l fish_plugins $__fish_config_dir/fish_plugins

if not test -f $plugins_list
    echo "setup.fish: $plugins_list not found" >&2
    exit 1
end

if set -q _flag_update; or not functions -q fisher
    curl -fsSL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
    or exit 1
    fisher install jorgebucaran/fisher </dev/null
end

# Blank lines, comments and duplicates out, the order of the list kept
string trim <$plugins_list | string match -rv '^(#|$)' | awk '!seen[$0]++' >$fish_plugins

# A fresh fish, so the plugins installed above are loaded the usual way
fish -c "fisher update </dev/null"
