#!/usr/bin/env bash
# @file test.sh
# @brief Run tests for the dotfiles setup
# @description Run the bats suite of this repository, or one of the schema
# validations on their own. The runner is the bats bundled with the dybatpho
# submodule, falling back to a bats already on `PATH`.
SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
# The library lives in a submodule, which a fresh clone or a new worktree
# does not populate. Fetch it before sourcing, or nothing below is defined.
if [[ ! -f "${SCRIPT_DIR}/lib/dybatpho/init.sh" ]]; then
  git -C "${SCRIPT_DIR}/.." submodule update --init "${SCRIPT_DIR}/lib/dybatpho"
fi
if [[ ! -f "${SCRIPT_DIR}/lib/dybatpho/init.sh" ]]; then
  echo "dybatpho is missing and could not be fetched." >&2
  echo "Run: git submodule update --init scripts/lib/dybatpho" >&2
  exit 1
fi
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/dybatpho/init.sh
. "${SCRIPT_DIR}/lib/dybatpho/init.sh" --modules cli parallel
# shellcheck source=lib/test_select.sh
. "${SCRIPT_DIR}/lib/test_select.sh"
BATS_CMD="${DYBATPHO_DIR}/test/lib/core/bin/bats"
dybatpho::register_common_handlers

#######################################
# @description Spec of test.sh
# @noargs
#######################################
function _spec_main {
  dybatpho::opts::setup "Test the dotfiles setup" MAIN_ARGS action:"_main"
  dybatpho::opts::flag "Run all tests" ALL --all -a on:true off:false init:="false"
  dybatpho::opts::flag "Run only the tests covering what changed since main" \
    CHANGED --changed -c on:true off:false init:="false"
  dybatpho::opts::flag "Run only the dytoy YAML schema validation tests" \
    DYTOY --dytoy -d on:true off:false init:="false"
  dybatpho::opts::flag "Run only the secrets YAML schema validation tests" \
    SECRETS --secrets -s on:true off:false init:="false"
  dybatpho::opts::flag "Run only the dyai YAML schema validation tests" \
    DYAI --dyai on:true off:false init:="false"
  dybatpho::opts::param "Test files to run at once, 0 for one per CPU, 1 for the full output" \
    JOBS --jobs -j init:="0" type:uint
  dybatpho::opts::disp "Show help" --help -h action:"dybatpho::generate_help _spec_main"
}

#######################################
# @description Run one bats file, named in its output
# @arg $1 string Path of the bats file
# @stdout One line for a file that passed, its whole TAP output otherwise:
# hundreds of `ok` lines are of no use to whoever reads the run
#######################################
function _run_bats_file {
  local file base output code=0
  dybatpho::expect_args file -- "$@"
  base="$(dybatpho::path_basename "${file}")"
  output="$("${BATS_CMD}" --print-output-on-failure --verbose-run "${file}" 2>&1)" || code=$?
  if ((code != 0)); then
    printf '# %s\n%s\n' "${base}" "${output}"
    return "${code}"
  fi
  local line tests=0 skipped=0
  while IFS= read -r line; do
    [[ "${line}" != ok\ * ]] || tests=$((tests + 1))
    [[ "${line}" != ok\ *"# skip"* ]] || skipped=$((skipped + 1))
  done <<< "${output}"
  printf 'ok %s (%d tests, %d skipped)\n' "${base}" "${tests}" "${skipped}"
}

#######################################
# @description Run bats files several at once, and fail when any of them did
# @arg $@ string Paths of the bats files
# @stdout The output of each file, whole and in order
#######################################
function _run_bats_files {
  # One bats per file, several at once: a serial run takes minutes, and
  # `bats --jobs` needs GNU parallel.
  if ! dybatpho::parallel_map "${JOBS}" _run_bats_file "$@"; then
    local failed
    failed="$(dybatpho::parallel_failed)"
    dybatpho::die "${failed} of $# test files failed"
  fi
}

#######################################
# @description Print the paths that differ from the main branch: the commits
# of the current branch, and what the working tree holds on top of them
# @noargs
# @stdout One path per line, relative to the repository root
#######################################
function _changed_paths {
  local base
  # quotepath off: a path is printed as it is, not quoted and escaped.
  local -a git=(git -C "${SCRIPT_DIR}/.." -c core.quotepath=off)
  if ! base="$("${git[@]}" merge-base HEAD main 2> /dev/null)"; then
    dybatpho::warn "No main branch to compare with: only the working tree counts as changed."
    base="HEAD"
  fi
  "${git[@]}" diff --name-only "${base}" HEAD
  # `status`, not `diff`: it lists untracked files too. A submodule counts
  # when its commit moved, not for a change left inside it.
  "${git[@]}" status --porcelain --no-renames --untracked-files=all \
    --ignore-submodules=dirty | cut -c4-
}

#######################################
# @description Run the tests covering what changed since the main branch
# @noargs
#######################################
function _run_changed {
  local paths selected
  paths="$(_changed_paths)"
  if [[ -z "${paths}" ]]; then
    dybatpho::info "Nothing changed since main, no test to run."
    return 0
  fi
  local -a changed=() files=()
  mapfile -t changed <<< "${paths}"
  selected="$(test_select::files "${SCRIPT_DIR}/.." ${changed[@]+"${changed[@]}"})"
  if [[ "${selected}" == "--all" ]]; then
    dybatpho::info "A changed file reaches every test, or is named by none: running the whole suite."
    mapfile -t files < <(printf '%s\n' "${SCRIPT_DIR}"/test/*.bats)
  elif [[ -z "${selected}" ]]; then
    dybatpho::info "Only documentation or deleted files changed, no test to run."
    return 0
  else
    mapfile -t files <<< "${selected}"
  fi
  _run_bats_files ${files[@]+"${files[@]}"}
}

#######################################
# @description Main function
# @noargs
#######################################
function _main {
  if [[ ! -x "${BATS_CMD}" ]]; then
    if dybatpho::is command bats; then
      BATS_CMD="$(dybatpho::command_path bats)"
    else
      git -C "${DYBATPHO_DIR}" submodule update --init --recursive 2> /dev/null || true
    fi
  fi
  if [[ ! -x "${BATS_CMD}" ]]; then
    local hint="git -C ${DYBATPHO_DIR} submodule update --init --recursive"
    dybatpho::die "Bats test runner not found. Install bats, or run: ${hint}"
  fi

  if [[ "${DYTOY}" == "true" ]]; then
    exec "${BATS_CMD}" --print-output-on-failure --verbose-run \
      "${SCRIPT_DIR}/test/dytoy_schema.bats"
  fi
  if [[ "${SECRETS}" == "true" ]]; then
    exec "${BATS_CMD}" --print-output-on-failure --verbose-run \
      "${SCRIPT_DIR}/test/secrets_schema.bats"
  fi
  if [[ "${DYAI}" == "true" ]]; then
    exec "${BATS_CMD}" --print-output-on-failure --verbose-run \
      "${SCRIPT_DIR}/test/dyai_schema.bats"
  fi
  if [[ "${ALL}" == "true" ]]; then
    if ((JOBS == 1)); then
      exec "${BATS_CMD}" --print-output-on-failure --verbose-run "${SCRIPT_DIR}/test"
    fi
    _run_bats_files "${SCRIPT_DIR}"/test/*.bats
    return 0
  fi
  if [[ "${CHANGED}" == "true" ]]; then
    _run_changed
    return 0
  fi
  if ((${#MAIN_ARGS[@]} > 0)); then
    exec "${BATS_CMD}" --print-output-on-failure --verbose-run "${MAIN_ARGS[@]}"
  fi

  dybatpho::die "No test specified. Use --all, --changed, --dytoy, --secrets, --dyai, or specify a test file."
}

dybatpho::generate_from_spec _spec_main "$@"
