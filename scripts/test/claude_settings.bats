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

@test "settings.json turns off the official LSP plugins dyai-lsp replaces" {
  _require_chezmoi
  local out="${BATS_TEST_TMPDIR}/settings.json"
  if ! _render_settings "${out}"; then
    fail "render failed: $(< "${out}.err")"
  fi
  local plugin
  for plugin in pyright-lsp lua-lsp typescript-lsp gopls-lsp rust-analyzer-lsp; do
    jq -e --arg p "${plugin}@claude-plugins-official" '.enabledPlugins[$p] == false' "${out}" > /dev/null \
      || fail "${plugin}@claude-plugins-official is not disabled"
  done
  jq -e '.enabledPlugins["dyai-lsp@dyai-lsp"] == true' "${out}" > /dev/null \
    || fail "dyai-lsp@dyai-lsp is not enabled"
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

@test "settings.json sandboxes bash, so Read denies hold for shell commands too" {
  _require_chezmoi
  local out="${BATS_TEST_TMPDIR}/settings.json"
  _render_settings "${out}" || fail "render failed: $(< "${out}.err")"
  jq -e '.sandbox.enabled == true' "${out}" > /dev/null
  jq -e '.permissions.disableBypassPermissionsMode == "disable"' "${out}" > /dev/null
  # rtk turns `cat` into `rtk read`; excluding rtk wholesale would let a
  # shell read of a denied path out of the sandbox again.
  jq -e '.sandbox.excludedCommands | all(test("^rtk( \\*)?$") | not)' "${out}" > /dev/null \
    || fail "rtk is excluded from the sandbox as a whole"
  jq -e '.sandbox.excludedCommands | all(test("^(cat|rtk read)") | not)' "${out}" > /dev/null
  # Nothing writable may contain a PATH directory or a tool's trust state:
  # an auto-approved sandboxed command could plant code that later runs
  # outside the sandbox.
  jq -e '.sandbox.filesystem as $fs | [$fs.allowWrite[] as $w | $fs.denyWrite[]
    | select(startswith($w + "/") or . == $w)] | length == 0' "${out}" > /dev/null \
    || fail "an allowWrite path contains a denyWrite one"
  jq -e '.sandbox.filesystem.allowWrite | all(. as $w
    | ["~", "~/.cache", "~/.local", "~/.local/state", "~/.local/share", "~/.claude"] | index($w) | not)' \
    "${out}" > /dev/null || fail "a broad home directory is writable from the sandbox"
  jq -e '.sandbox.filesystem.denyWrite | index("~/.local/bin") != null and index("~/.cache/.bun/bin") != null' \
    "${out}" > /dev/null
  # Only download hosts: a host that accepts writes would let a sandboxed
  # command send data out without a prompt.
  jq -e '.sandbox.network.allowedDomains | all(. as $d
    | ["github.com", "*.github.com", "api.github.com", "gitlab.com", "*"] | index($d) | not)' \
    "${out}" > /dev/null || fail "a write-capable host is in the sandbox allowlist"
  # git is excluded in both spellings, or commits in a worktree fail.
  jq -e '.sandbox.excludedCommands | index("git *") != null and index("rtk git *") != null' \
    "${out}" > /dev/null
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
