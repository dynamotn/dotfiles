setup() {
  load test_helper
  SETTINGS_TMPL="${DOTFILES_DIR}/home/private_dot_claude/settings.json.tmpl"
  EXPECTED="${DOTFILES_DIR}/scripts/test/fixtures/claude-settings.expected.json"
}

function _require_chezmoi {
  command -v chezmoi &> /dev/null || skip "chezmoi not found"
}

function _render_settings {
  local out="${1}"
  (
    cd "${DOTFILES_DIR}" || exit 1
    env HOME="${DOTFILES_REAL_HOME}" \
      XDG_CONFIG_HOME="${DOTFILES_REAL_XDG_CONFIG_HOME:-${DOTFILES_REAL_HOME}/.config}" \
      chezmoi execute-template --source "${DOTFILES_DIR}" \
      < "${SETTINGS_TMPL}" > "${out}" 2> "${out}.err"
  )
}

@test "settings.json.tmpl renders valid JSON" {
  _require_chezmoi
  local out="${BATS_TEST_TMPDIR}/settings.json"
  _render_settings "${out}" || fail "render failed: $(cat "${out}.err")"
  jq empty "${out}" || fail "rendered settings.json is not valid JSON"
}

@test "settings.json.tmpl matches the pre-dyai settings.json exactly" {
  _require_chezmoi
  local out="${BATS_TEST_TMPDIR}/settings.json"
  _render_settings "${out}" || fail "render failed: $(cat "${out}.err")"
  # Order-independent full-document equality against the captured baseline.
  diff <(jq -S . "${out}") "${EXPECTED}" \
    || fail "rendered settings.json differs from the pre-dyai baseline"
}
