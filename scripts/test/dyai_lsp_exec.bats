setup() {
  load test_helper
  setup_dotfiles_test_env
  # shellcheck disable=SC2154 # DOTFILES_DIR is set by test_helper.bash
  . "${DOTFILES_DIR}/scripts/lib/dyai_lsp_exec.sh"
  # shellcheck disable=SC2154 # BATS_TEST_TMPDIR is set by bats itself
  export DYAI_LSP_MANIFEST="${BATS_TEST_TMPDIR}/lsp.json"
}

@test "dyai-lsp-exec execs the server outside a held dir, passing stdio and exit code" {
  cd "${BATS_TEST_TMPDIR}" && run dyai_lsp_exec::main x -- bash -c 'cat; exit 7' <<< "hi"
  [[ "${status}" == 7 && "${output}" == "hi" ]]
}

@test "dyai-lsp-exec refuses inside a dyreview worktree, also through a symlink" {
  d="${BATS_TEST_TMPDIR}/repo/.worktrees/dyreview-42/src"
  mkdir -p "${d}"
  ln -s "${d}" "${BATS_TEST_TMPDIR}/link"
  cd "${BATS_TEST_TMPDIR}/link" && run dyai_lsp_exec::main pyls -- true
  [[ "${status}" == 3 && "${output}" == *"held untrusted"* ]]
}

@test "dyai-lsp-exec fails closed on dyreview with a missing or invalid manifest, open elsewhere" {
  printf 'not json' > "${DYAI_LSP_MANIFEST}"
  run dyai_lsp_exec::held "${BATS_TEST_TMPDIR}/x/.worktrees/dyreview-1" "${DYAI_LSP_MANIFEST}"
  assert_success
  run dyai_lsp_exec::held "${BATS_TEST_TMPDIR}/plain dir with space" "${DYAI_LSP_MANIFEST}"
  assert_failure
}

@test "dyai-lsp-exec uses the manifest regexes when present" {
  jq -n '{version:1, untrusted_regexes:["/held(/|$)"], servers:[]}' > "${DYAI_LSP_MANIFEST}"
  run dyai_lsp_exec::held "${BATS_TEST_TMPDIR}/held" "${DYAI_LSP_MANIFEST}"
  assert_success
}

@test "dyai-lsp-exec rejects a missing -- or missing command with a usage error" {
  run dyai_lsp_exec::main x
  assert_failure
  run dyai_lsp_exec::main x notdoubledash true
  assert_failure
  run dyai_lsp_exec::main x --
  assert_failure
}
