# dyshellint disable=SC2154 DOTFILES_DIR, DOTFILES_REAL_* and BATS_TEST_TMPDIR come from bats and test_helper
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
  _render_settings "${out}" || fail "render failed: $(< "${out}.err")"
  jq empty "${out}" || fail "rendered settings.json is not valid JSON"
}

@test "settings.json.tmpl matches the pre-dyai settings.json exactly" {
  _require_chezmoi
  local out="${BATS_TEST_TMPDIR}/settings.json"
  _render_settings "${out}" || fail "render failed: $(< "${out}.err")"
  # Order-independent full-document equality against the captured baseline.
  jq -S . "${out}" > "${out}.sorted"
  diff "${out}.sorted" "${EXPECTED}" \
    || fail "rendered settings.json differs from the pre-dyai baseline"
}

@test "settings.json enforces no commit or PR attribution" {
  _require_chezmoi
  local out="${BATS_TEST_TMPDIR}/settings.json"
  _render_settings "${out}" || fail "render failed: $(< "${out}.err")"
  jq -e '.attribution.commit == ""' "${out}" > /dev/null
  jq -e '.attribution.pr == ""' "${out}" > /dev/null
}

@test "settings.json denies the credential stores to Read and Edit" {
  _require_chezmoi
  local out="${BATS_TEST_TMPDIR}/settings.json"
  _render_settings "${out}" || fail "render failed: $(< "${out}.err")"
  local rule
  for rule in 'Read(**/secrets/data/**)' 'Edit(**/secrets/data/**)' \
    'Read(~/.ssh/**)' 'Read(**/*.age)' 'Bash(chezmoi-dycrypt:*)'; do
    jq -e --arg r "${rule}" '.permissions.deny | index($r) != null' "${out}" > /dev/null \
      || fail "missing deny rule ${rule}"
  done
}

@test "every git ask rule also covers its rtk rewrite" {
  _require_chezmoi
  local out="${BATS_TEST_TMPDIR}/settings.json"
  _render_settings "${out}" || fail "render failed: $(< "${out}.err")"
  # The rtk PreToolUse hook turns `git push` into `rtk git push`; a rule
  # without the rtk spelling would be bypassed by that rewrite. A `p:*` rule
  # is covered by either `rtk p:*` or `rtk p *`.
  local missing
  missing="$(jq -r '.permissions.ask as $a
    | $a[] | select(startswith("Bash(git "))
    | ("Bash(rtk " + ltrimstr("Bash(")) as $r
    | [$r, ($r | sub(":\\*\\)$"; " *)"))] as $ok
    | select([$ok[] | . as $x | $a | index($x)] | all(. == null)) | $r' "${out}")"
  [[ -z "${missing}" ]] || fail "ask rules without an rtk variant: ${missing}"
}
