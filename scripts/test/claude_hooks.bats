# dyshellint disable=SC2154 DOTFILES_DIR and BATS_TEST_TMPDIR come from bats and test_helper
# dyshellint disable=SC2016 the fixtures write a literal $1 for dyshellint to flag
setup() {
  load test_helper
  HOOK="${DOTFILES_DIR}/home/private_dot_claude/hooks/executable_lint-shell.sh"
  WORK="${BATS_TEST_TMPDIR}/work"
  mkdir -p "${WORK}"
}

function _require_dyshellint {
  command -v dyshellint &> /dev/null || skip "dyshellint not found"
}

# Feed the hook the PostToolUse input of an edit of $1.
function _run_hook {
  local input
  input="$(jq -cn --arg f "${1}" '{tool_input: {file_path: $f}}')"
  run --separate-stderr bash "${HOOK}" <<< "${input}"
}

@test "lint-shell hook is itself clean under dyshellint" {
  _require_dyshellint
  # The source carries chezmoi's executable_ prefix instead of the bit.
  run dyshellint -warnings-as-errors -exclude-rules BSG037 "${HOOK}"
  assert_success
}

@test "lint-shell hook reports warnings, not only errors" {
  _require_dyshellint
  printf '#!/usr/bin/env bash\n# @file w.sh\n# @brief W\n# @description W.\nset -euo pipefail\nx="a"\necho "$x"\n' \
    > "${WORK}/warn.sh"
  chmod +x "${WORK}/warn.sh"
  run dyshellint "${WORK}/warn.sh"
  # Precondition: dyshellint alone passes this file with warnings only.
  assert_success
  _run_hook "${WORK}/warn.sh"
  [[ "${status}" -eq 2 ]] || fail "expected exit 2, got ${status}"
}

@test "lint-shell hook feeds dyshellint findings back with exit 2" {
  _require_dyshellint
  printf 'x=$1\necho $x\n' > "${WORK}/bad.sh"
  _run_hook "${WORK}/bad.sh"
  [[ "${status}" -eq 2 ]] || fail "expected exit 2, got ${status}"
  [[ "${stderr}" == *"dyshellint reported findings"* ]]
  [[ "${stderr}" == *"SC2086"* ]]
}

@test "lint-shell hook passes a clean script silently" {
  _require_dyshellint
  _run_hook "${HOOK}"
  assert_success
  [[ -z "${stderr}" ]]
}

@test "lint-shell hook recognizes an extensionless script by its shebang" {
  _require_dyshellint
  printf '#!/usr/bin/env bash\necho $1\n' > "${WORK}/tool"
  _run_hook "${WORK}/tool"
  [[ "${status}" -eq 2 ]] || fail "expected exit 2, got ${status}"
}

@test "lint-shell hook ignores templates, other files and missing paths" {
  _require_dyshellint
  printf 'echo {{ .x }} $1\n' > "${WORK}/a.sh.tmpl"
  printf '# notes $1\n' > "${WORK}/notes.md"
  local f
  for f in "${WORK}/a.sh.tmpl" "${WORK}/notes.md" "${WORK}/missing.sh"; do
    _run_hook "${f}"
    assert_success
  done
}

@test "lint-shell hook is a no-op without dyshellint on PATH" {
  printf 'echo $1\n' > "${WORK}/bad.sh"
  PATH="/usr/bin:/bin" _run_hook "${WORK}/bad.sh"
  assert_success
}

@test "settings.json wires the lint-shell hook on Edit and Write" {
  local tmpl="${DOTFILES_DIR}/home/private_dot_claude/settings.json.tmpl"
  grep -q 'lint-shell.sh' "${tmpl}"
}
