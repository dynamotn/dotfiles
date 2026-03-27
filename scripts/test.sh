#!/usr/bin/env bash
# @file test.sh
# @brief Run tests for the dotfiles setup
SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
# shellcheck source=lib/dybatpho/init.sh
. "$SCRIPT_DIR/lib/dybatpho/init.sh"
BATS_CMD="${DYBATPHO_DIR}/test/lib/core/bin/bats"
dybatpho::register_common_handlers

#######################################
# @description Spec of test.sh
#######################################
function _spec_main {
  dybatpho::opts::setup "Test the dotfiles setup" MAIN_ARGS action:"_main"
  dybatpho::opts::flag "Run all tests" ALL --all -a on:true off:false init:="false"
  dybatpho::opts::flag "Run only the dytoy YAML schema validation tests" DYTOY --dytoy -d on:true off:false init:="false"
  dybatpho::opts::flag "Run only the secrets YAML schema validation tests" SECRETS --secrets -s on:true off:false init:="false"
  dybatpho::opts::disp "Show help" --help -h action:"dybatpho::generate_help _spec_main"
}

#######################################
# @description Main function
#######################################
function _main {
  if [ "$DYTOY" = "true" ]; then
    exec "${BATS_CMD}" --print-output-on-failure --verbose-run \
      "${SCRIPT_DIR}/test/dytoy_schema.bats"
  fi
  if [ "$SECRETS" = "true" ]; then
    exec "${BATS_CMD}" --print-output-on-failure --verbose-run \
      "${SCRIPT_DIR}/test/secrets_schema.bats"
  fi
  if [ "$ALL" = "true" ]; then
    exec "${BATS_CMD}" --print-output-on-failure --verbose-run "${SCRIPT_DIR}/test"
  fi

  dybatpho::error "No test specified. Use --all, --schema or --secrets."
}

dybatpho::generate_from_spec _spec_main "$@"
