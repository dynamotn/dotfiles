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
  local before
  before="$(cat "${f}")"
  run bash "${HOOK}"
  assert_success
  [[ "$(cat "${f}")" == "${before}" ]]
}

@test "gemini: baseline settings set, user keys kept, idempotent" {
  _stub_agent gemini
  dybatpho::ensure_dir "${HOME}/.gemini" > /dev/null
  printf '{"ui":{"theme":"x"},"general":{"vimMode":true}}' > "${HOME}/.gemini/settings.json"
  _write_config
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.gemini/settings.json"
  jq -e '.["$schema"] | endswith("/schemas/settings.schema.json")' "${f}" > /dev/null
  jq -e '.context.fileName == ["AGENTS.md", "GEMINI.md"]' "${f}" > /dev/null
  jq -e '.general.checkpointing.enabled and .general.vimMode' "${f}" > /dev/null
  jq -e '.security.disableYoloMode' "${f}" > /dev/null
  jq -e '.privacy.usageStatisticsEnabled == false and .telemetry.enabled == false' "${f}" > /dev/null
  jq -e '.ui.theme == "x"' "${f}" > /dev/null
  local before
  before="$(cat "${f}")"
  run bash "${HOOK}"
  assert_success
  run cat "${f}"
  assert_output "${before}"
}

@test "approval accept-edits sets opencode edit=allow" {
  _stub_agent opencode
  _write_config
  run bash "${HOOK}"
  assert_success
  [[ "$(jq -r '.permission.edit' "${HOME}/.config/opencode/opencode.json")" == "allow" ]]
}

@test "approval accept-edits sets codex workspace-write and on-request" {
  _stub_agent codex
  _write_config
  local f="${HOME}/.codex/config.toml"
  mkdir -p "${HOME}/.codex"
  # A table already in the file must not swallow the new top-level keys.
  printf '[[hooks.Stop]]\nhooks = [{ type = "command", command = "x" }]\n' > "${f}"
  run bash "${HOOK}"
  assert_success
  yq -p=toml -e '.sandbox_mode == "workspace-write"' "${f}" > /dev/null
  yq -p=toml -e '.approval_policy == "on-request"' "${f}" > /dev/null
}

@test "approval keeps codex values the user already set" {
  _stub_agent codex
  _write_config
  mkdir -p "${HOME}/.codex"
  printf 'sandbox_mode = "read-only"\napproval_policy = "untrusted"\n' > "${HOME}/.codex/config.toml"
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.codex/config.toml"
  yq -p=toml -e '.sandbox_mode == "read-only"' "${f}" > /dev/null
  yq -p=toml -e '.approval_policy == "untrusted"' "${f}" > /dev/null
}
