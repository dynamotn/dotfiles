#!/usr/bin/env bash
# @file misc.sh
# @brief Library `misc` for helpers that fit no other library
# @description Library `misc` for helpers that fit no other library, such as installing a
# tool through dytoy and substituting a version into a release asset name.
#######################################
# @description Install tool using dytoy
# @arg $1 string Name of tool
#######################################
function misc::install_tool {
  local name
  dybatpho::expect_args name -- "$@"
  dybatpho::is command "${name}" && return 0
  local dytoy_bin
  dytoy_bin="$(dybatpho::path_join "${HOME}" ".local" "bin" "dytoy")"
  dybatpho::dry_run "${dytoy_bin}" -t "${name}"
}

#######################################
# @description Replace version of tool in release assets file name or hook scripts.
# `%v` takes the version as is, `%1v` without its leading `v`.
# @arg $1 string Version of tool
# @stdin $2 string Input stream
#######################################
function misc::replace_version {
  local version
  dybatpho::expect_args version -- "$@"
  # Plain substitution rather than `sed`, which choked on a tag holding `/` or
  # `&`. A tag without a leading `v` keeps its first digit under `%1v`. The
  # pattern and replacement are quoted, so neither is read as a glob or `&`.
  local line
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line//"%1v"/"${version#v}"}"
    printf '%s\n' "${line//"%v"/"${version}"}"
  done
}
