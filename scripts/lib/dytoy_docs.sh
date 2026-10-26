# @file dytoy_docs.sh
# @brief Read the doc blocks at the top of dytoy tool definitions
# @description A definition may start with `{{- /* doc` ... `*/ -}}` comment
# blocks holding YAML that describes the tool for `docs/dytoy.md`. These
# helpers read the blocks and give back the file without them, using plain
# text only (no chezmoi rendering). Blocks only count before the first line
# that is neither inside a block nor an opener; a later opener is ordinary
# text. Sourced (not executed); the caller sources dybatpho first.
# shellcheck shell=bash

#######################################
# @description Scan the leading blocks of a file
# @arg $1 string `blocks` prints block bodies, `strip` prints the rest
# @arg $2 string Definition file
# @stdout Block bodies separated by `---`, or the file without its blocks
# @exitcode 3 A block has no closing line
#######################################
function dytoy_docs::scan {
  dybatpho::expect_args mode file -- "$@"
  awk -v mode="$1" '
    state != 2 && /^\{\{- \/\* doc$/ { state = 1; if (mode == "blocks" && n++) print "---"; next }
    state == 1 && /^\*\/ -\}\}$/ { state = 0; next }
    state == 1 { if (mode == "blocks") print; next }
    { state = 2; if (mode == "strip") print }
    END { if (state == 1) exit 3 }
  ' "$2"
}

#######################################
# @description Print every doc block as a YAML document, with a `file` key added
# @arg $1 string Definition file
# @stdout YAML documents separated by `---`; nothing when there is no block
# @exitcode 1 A block has no closing line
#######################################
function dytoy_docs::blocks {
  dybatpho::expect_args file -- "$@"
  local file="$1" base body
  base="$(basename "${file}")"
  body="$(dytoy_docs::scan blocks "${file}")" \
    || dybatpho::die "${file}: doc block is not closed with '*/ -}}'"
  [[ -n "${body}" ]] || return 0
  BASE="${base}" yq '.file = strenv(BASE)' <<< "${body}"
}

#######################################
# @description Print the file with every leading doc block removed
# @arg $1 string Definition file
# @stdout File text without the blocks
# @exitcode 1 A block has no closing line
#######################################
function dytoy_docs::strip {
  dybatpho::expect_args file -- "$@"
  dytoy_docs::scan strip "$1" \
    || dybatpho::die "$1: doc block is not closed with '*/ -}}'"
}
