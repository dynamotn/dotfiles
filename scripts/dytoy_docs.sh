#!/usr/bin/env bash
# @file dytoy_docs.sh
# @brief Regenerate the tool tables of docs/dytoy.md
# @description Rebuild the generated region of `docs/dytoy.md` from the doc
# blocks of the dytoy definitions, `docs/dytoy.extra.yaml` and the order in
# `docs/dytoy.categories.yaml`. Runs as a pre-commit hook: it fails when the
# doc changed, so the regenerated file gets staged before the commit lands.
# `DYTOY_DOCS_ROOT` points it at another repository root, for tests.
SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/dybatpho/init.sh
. "${SCRIPT_DIR}/lib/dybatpho/init.sh" --modules cli file
# shellcheck source=lib/dytoy_docs.sh
. "${SCRIPT_DIR}/lib/dytoy_docs.sh"
dybatpho::register_common_handlers
shopt -s inherit_errexit

#######################################
# @description Spec of dytoy_docs.sh
# @noargs
#######################################
function _spec_main {
  dybatpho::opts::setup "Regenerate the tool tables of docs/dytoy.md" MAIN_ARGS action:"_main"
  dybatpho::opts::flag "Only report whether the doc is out of date, write nothing" \
    CHECK --check -c on:true off:false init:="false"
  dybatpho::opts::disp "Show help" --help -h action:"dybatpho::generate_help _spec_main"
}

#######################################
# @description Main function
# @noargs
#######################################
# dyshellint disable=SC2154 CHECK is assigned by dybatpho::opts from _spec_main
function _main {
  local root doc json generated target changed=0
  root="${DYTOY_DOCS_ROOT:-$(realpath "${SCRIPT_DIR}/..")}"
  doc="${root}/docs/dytoy.md"
  dybatpho::create_temp json ".json"
  dytoy_docs::collect "${root}/home/.chezmoitemplates/dytoy" \
    "${root}/docs/dytoy.extra.yaml" "${root}/docs/dytoy.categories.yaml" > "${json}"
  dybatpho::create_temp generated ".md"
  dytoy_docs::render "${root}/docs/dytoy.categories.yaml" < "${json}" > "${generated}"
  target="${doc}"
  if [[ "${CHECK}" == "true" ]]; then
    dybatpho::create_temp target ".md"
    cp "${doc}" "${target}"
  fi
  # dyshellint disable=SC2310 update reports "changed" through its status; a missing marker still dies inside it
  dytoy_docs::update "${target}" "${generated}" || changed=1
  ((changed)) || return 0
  if [[ "${CHECK}" == "true" ]]; then
    dybatpho::die "docs/dytoy.md is out of date, run scripts/dytoy_docs.sh"
  fi
  dybatpho::die "docs/dytoy.md regenerated, re-stage it"
}

dybatpho::generate_from_spec _spec_main "$@"
