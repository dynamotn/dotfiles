# @file dytoy_docs.sh
# @brief Read the doc blocks at the top of dytoy tool definitions
# @description A definition may start with `{{- /* doc` ... `*/ -}}` comment
# blocks holding YAML that describes the tool for `docs/dytoy.md`. These
# helpers read the blocks and give back the file without them, using plain
# text only (no chezmoi rendering). Sourced (not executed); the caller sources
# dybatpho first.
# shellcheck shell=bash

#######################################
# @description Print every doc block as a YAML document, with a `file` key added
# @arg $1 string Definition file
# @stdout YAML documents separated by `---`; nothing when there is no block
#######################################
function dytoy_docs::blocks {
  dybatpho::expect_args file -- "$@"
  local file="$1" base body
  base="$(basename "${file}")"
  body="$(awk '
    /^\{\{- \/\* doc$/ { if (n++) print "---"; inb = 1; next }
    /^\*\/ -\}\}$/ { inb = 0; next }
    inb { print }
  ' "${file}")"
  [[ -n "${body}" ]] || return 0
  BASE="${base}" yq '.file = strenv(BASE)' <<< "${body}"
}

#######################################
# @description Print the file with every doc block removed
# @arg $1 string Definition file
# @stdout File text without the blocks
#######################################
function dytoy_docs::strip {
  dybatpho::expect_args file -- "$@"
  awk '
    /^\{\{- \/\* doc$/ { inb = 1; next }
    inb && /^\*\/ -\}\}$/ { inb = 0; next }
    !inb { print }
  ' "$1"
}
