setup() {
  load test_helper
  setup_dotfiles_test_env
  HOOK="${BATS_TEST_TMPDIR}/setup-ai.sh"
  LAYA="${HOME}/.local/bin/laya-mcp-server"
  : > "${LAYA}" && chmod +x "${LAYA}"
  render_template "home/.chezmoiscripts/run_onchange_after_03-setup-ai.sh.tmpl" "${HOOK}"
}

function _stub_agent {
  printf '#!/usr/bin/env bash\nexit 0\n' > "${HOME}/.local/bin/${1}"
  chmod +x "${HOME}/.local/bin/${1}"
}

function _write_config {
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${HOME}/.config/dyai/config.yaml" << EOF
global:
  skills: []
  mcp:
    laya:
      command: ${LAYA}
      args: []
      env: {}
  policy:
    approval: accept-edits
agents:
  claude: {}
EOF
}

@test "approval accept-edits sets gemini auto_edit, preserves other keys, idempotent" {
  _stub_agent gemini
  dybatpho::ensure_dir "${HOME}/.gemini" > /dev/null
  printf '{"ui":{"theme":"x"}}' > "${HOME}/.gemini/settings.json"
  _write_config
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.gemini/settings.json"
  [[ "$(jq -r '.general.defaultApprovalMode' "${f}")" == "auto_edit" ]]
  [[ "$(jq -r '.ui.theme' "${f}")" == "x" ]]
  local before; before="$(cat "${f}")"
  run bash "${HOOK}"
  assert_success
  [[ "$(cat "${f}")" == "${before}" ]]
}

@test "approval accept-edits sets opencode edit=allow" {
  _stub_agent opencode
  _write_config
  run bash "${HOOK}"
  assert_success
  [[ "$(jq -r '.permission.edit' "${HOME}/.config/opencode/opencode.json")" == "allow" ]]
}

@test "approval is NOT written for agents without a clean edits-only preset" {
  _stub_agent codex
  _write_config
  run bash "${HOOK}"
  assert_success
  # codex got its MCP server but no approval_policy from dyai.
  local f="${HOME}/.codex/config.toml"
  [ -f "${f}" ]
  [[ "$(yq -p=toml '.approval_policy // "none"' "${f}")" == "none" ]]
}
