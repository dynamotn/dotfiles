setup() {
  load test_helper
  setup_dotfiles_test_env
  HOOK_SRC="home/.chezmoiscripts/run_onchange_after_03-setup-ai.sh.tmpl"
  HOOK="${BATS_TEST_TMPDIR}/setup-ai.sh"
  CLAUDE_LOG="${HOME}/claude.log"
  BUNX_LOG="${HOME}/bunx.log"
  _stub_cmd claude "${CLAUDE_LOG}" 0
  _stub_cmd bunx "${BUNX_LOG}" 0
}

# Write a stub on PATH that logs its args and exits with the given code.
function _stub_cmd {
  local name="${1}" log="${2}" code="${3}"
  cat > "${HOME}/.local/bin/${name}" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${log}"
exit ${code}
EOF
  chmod +x "${HOME}/.local/bin/${name}"
}

# Write a dyai config with laya pointing at an executable stub.
function _write_config {
  local laya="${HOME}/.local/bin/laya-mcp-server"
  : > "${laya}" && chmod +x "${laya}"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${HOME}/.config/dyai/config.yaml" << EOF
global:
  skills:
    - owner/repo@alpha
    - owner/repo@beta
  mcp:
    laya:
      command: ${laya}
      args: []
      env:
        HF_HUB_DISABLE_TELEMETRY: "1"
agents:
  claude:
    marketplaces:
      mk-one:
        source: { source: github, repo: owner/mk-one }
    plugins:
      - alpha@mk-one
      - beta@mk-one
EOF
}

@test "setup-ai installs marketplaces, plugins, skills and the laya MCP from dyai" {
  render_template "${HOOK_SRC}" "${HOOK}"
  _write_config
  run bash "${HOOK}"
  assert_success
  assert [ -f "${CLAUDE_LOG}" ]
  grep -q 'plugin marketplace add owner/mk-one' "${CLAUDE_LOG}"
  grep -q 'plugin install alpha@mk-one' "${CLAUDE_LOG}"
  grep -q 'plugin install beta@mk-one' "${CLAUDE_LOG}"
  grep -q 'mcp add-json --scope user laya' "${CLAUDE_LOG}"
  grep -q 'add owner/repo@alpha -g -y' "${BUNX_LOG}"
  grep -q 'add owner/repo@beta -g -y' "${BUNX_LOG}"
}

@test "setup-ai warns and skips when the dyai config is missing" {
  render_template "${HOOK_SRC}" "${HOOK}"
  # no _write_config: the file does not exist
  run bash "${HOOK}"
  assert_success
  assert_output --partial "dyai config not found"
  [ ! -f "${CLAUDE_LOG}" ] || ! grep -q 'plugin install' "${CLAUDE_LOG}"
}

@test "setup-ai warns but still exits zero when a marketplace cannot be added" {
  _stub_cmd claude "${CLAUDE_LOG}" 1
  render_template "${HOOK_SRC}" "${HOOK}"
  _write_config
  run bash "${HOOK}"
  assert_success
  assert_output --partial "Could not add marketplace mk-one"
}

@test "setup-ai warns but still exits zero on a malformed mcp section" {
  render_template "${HOOK_SRC}" "${HOOK}"
  _write_config
  # Corrupt global.mcp into a scalar.
  sed -i 's/^  mcp:$/  mcp: "broken"/' "${HOME}/.config/dyai/config.yaml"
  sed -i '/^    laya:$/,/HF_HUB/d' "${HOME}/.config/dyai/config.yaml"
  run bash "${HOOK}"
  assert_success
}
