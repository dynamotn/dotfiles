#!/usr/bin/env bash
#######################################
# @description Install tool using dytoy
# @arg $1 string Name of tool
#######################################
function misc::install_tool {
  local name
  dybatpho::expect_args name -- "$@"
  hash "$name" > /dev/null 2>&1 \
    || dybatpho::dry_run "$HOME/.local/bin/dytoy" -t "$name"
}

#######################################
# @description Replace version of tool in release assets file name or hook scripts
# @arg $1 string Version of tool
# @stdin $2 string Input stream
#######################################
function misc::replace_version {
  local version
  dybatpho::expect_args version -- "$@"
  cat - | sed "s/%v/${version}/g" | sed "s/%1v/${version:1}/g"
}
