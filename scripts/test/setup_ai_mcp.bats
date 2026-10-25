setup() {
  load test_helper
  setup_dotfiles_test_env
  HOOK_SRC="home/.chezmoiscripts/run_onchange_after_03-setup-ai.sh.tmpl"
  HOOK="${BATS_TEST_TMPDIR}/setup-ai.sh"
  LAYA="${HOME}/.local/bin/laya-mcp-server"
  : > "${LAYA}" && chmod +x "${LAYA}"
  render_template "${HOOK_SRC}" "${HOOK}"
}

# A stub agent binary on PATH so `command -v <name>` succeeds.
function _stub_agent {
  printf '#!/usr/bin/env bash\nexit 0\n' > "${HOME}/.local/bin/${1}"
  chmod +x "${HOME}/.local/bin/${1}"
}

# A dyai config whose only MCP server is laya (stdio, executable above).
function _write_config {
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${HOME}/.config/dyai/config.yaml" << EOF
global:
  skills: []
  mcp:
    laya:
      command: ${LAYA}
      args: []
      env:
        HF_HUB_DISABLE_TELEMETRY: "1"
agents:
  claude: {}
EOF
}

@test "gemini: laya merged into ~/.gemini/settings.json, other keys preserved, idempotent" {
  _stub_agent gemini
  dybatpho::ensure_dir "${HOME}/.gemini" > /dev/null
  printf '{"theme":"x","mcpServers":{"other":{"command":"o"}}}' > "${HOME}/.gemini/settings.json"
  _write_config
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.gemini/settings.json"
  [[ "$(jq -r '.mcpServers.laya.command' "${f}")" == "${LAYA}" ]]
  [[ "$(jq -r '.mcpServers.laya.env.HF_HUB_DISABLE_TELEMETRY' "${f}")" == "1" ]]
  [[ "$(jq -r '.theme' "${f}")" == "x" ]]
  [[ "$(jq -r '.mcpServers.other.command' "${f}")" == "o" ]]
  local before; before="$(cat "${f}")"
  run bash "${HOOK}"
  assert_success
  [[ "$(cat "${f}")" == "${before}" ]]
}

@test "agy: laya merged into ~/.gemini/config/mcp_config.json" {
  _stub_agent agy
  _write_config
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.gemini/config/mcp_config.json"
  [[ "$(jq -r '.mcpServers.laya.command' "${f}")" == "${LAYA}" ]]
}

@test "copilot: laya merged with type=local and tools=[*]" {
  _stub_agent copilot
  _write_config
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.copilot/mcp-config.json"
  [[ "$(jq -r '.mcpServers.laya.type' "${f}")" == "local" ]]
  [[ "$(jq -r '.mcpServers.laya.tools[0]' "${f}")" == "*" ]]
  [[ "$(jq -r '.mcpServers.laya.command' "${f}")" == "${LAYA}" ]]
}

@test "opencode: laya in mcp block with combined command array and environment" {
  _stub_agent opencode
  _write_config
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.config/opencode/opencode.json"
  [[ "$(jq -r '.mcp.laya.type' "${f}")" == "local" ]]
  [[ "$(jq -r '.mcp.laya.command[0]' "${f}")" == "${LAYA}" ]]
  [[ "$(jq -r '.mcp.laya.environment.HF_HUB_DISABLE_TELEMETRY' "${f}")" == "1" ]]
  [[ "$(jq -r '.mcp.laya.enabled' "${f}")" == "true" ]]
}

@test "codex: laya in config.toml mcp_servers with env table, unrelated key preserved" {
  _stub_agent codex
  dybatpho::ensure_dir "${HOME}/.codex" > /dev/null
  printf 'model = "gpt-5"\n' > "${HOME}/.codex/config.toml"
  _write_config
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.codex/config.toml"
  [[ "$(yq -p=toml -r '.mcp_servers.laya.command' "${f}")" == "${LAYA}" ]]
  [[ "$(yq -p=toml -r '.mcp_servers.laya.env.HF_HUB_DISABLE_TELEMETRY' "${f}")" == "1" ]]
  [[ "$(yq -p=toml -r '.model' "${f}")" == "gpt-5" ]]
}

@test "hermes: laya in config.yaml mcp_servers, unrelated key preserved" {
  _stub_agent hermes
  dybatpho::ensure_dir "${HOME}/.hermes" > /dev/null
  printf 'channel: stable\n' > "${HOME}/.hermes/config.yaml"
  _write_config
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.hermes/config.yaml"
  [[ "$(yq -r '.mcp_servers.laya.command' "${f}")" == "${LAYA}" ]]
  [[ "$(yq -r '.channel' "${f}")" == "stable" ]]
}

@test "no MCP config is written for agents that are not installed" {
  _write_config
  # A clean PATH with only the tools the hook needs, so no real agent on this
  # machine is discovered — proving the command -v gate, not the host's install set.
  local cleanbin="${BATS_TEST_TMPDIR}/cleanbin"
  mkdir -p "${cleanbin}"
  ln -s "$(command -v jq)" "${cleanbin}/jq"
  ln -s "$(command -v yq)" "${cleanbin}/yq"
  PATH="${cleanbin}:/usr/bin:/bin" run bash "${HOOK}"
  assert_success
  [ ! -f "${HOME}/.gemini/settings.json" ]
  [ ! -f "${HOME}/.gemini/config/mcp_config.json" ]
  [ ! -f "${HOME}/.copilot/mcp-config.json" ]
  [ ! -f "${HOME}/.config/opencode/opencode.json" ]
  [ ! -f "${HOME}/.codex/config.toml" ]
  [ ! -f "${HOME}/.hermes/config.yaml" ]
}

@test "codex: a second run is a no-op even with a pre-existing section-style server" {
  _stub_agent codex
  dybatpho::ensure_dir "${HOME}/.codex" > /dev/null
  # Section-style table, as `codex mcp add` itself writes it.
  printf '[mcp_servers.other]\ncommand = "o"\n' > "${HOME}/.codex/config.toml"
  _write_config
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.codex/config.toml"
  # Second run must reach the no-op branch, not rewrite (a rewrite strips the
  # user's TOML comments and churns the file on every apply).
  run bash "${HOOK}"
  assert_success
  refute_output --partial "Registered MCP laya in ${f}"
  # The pre-existing server survived.
  [[ "$(yq -p=toml -r '.mcp_servers.other.command' "${f}")" == "o" ]]
}

@test "a malformed pre-existing agent config warns and the hook still processes the rest" {
  _stub_agent gemini
  _stub_agent codex
  dybatpho::ensure_dir "${HOME}/.gemini" > /dev/null
  printf '{ this is not json' > "${HOME}/.gemini/settings.json"
  _write_config
  run bash "${HOOK}"
  assert_success
  # codex, processed after gemini, still got laya — the hook did not abort.
  [[ "$(yq -p=toml -r '.mcp_servers.laya.command' "${HOME}/.codex/config.toml")" == "${LAYA}" ]]
}

@test "a bunx-launched MCP server is registered (PATH-aware command gate)" {
  _stub_agent gemini
  _stub_agent bunx
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${HOME}/.config/dyai/config.yaml" << 'CFG'
global:
  skills: []
  mcp:
    seqthink:
      command: bunx
      args: ["@modelcontextprotocol/server-sequential-thinking@2.0.0"]
      env: {}
agents:
  claude: {}
CFG
  run bash "${HOOK}"
  assert_success
  [[ "$(jq -r '.mcpServers.seqthink.command' "${HOME}/.gemini/settings.json")" == "bunx" ]]
}

@test "filesystem scopes to enterprise in an enterprise config dir, personal+community by default" {
  cat > "${HOME}/.local/bin/claude" << CL
#!/usr/bin/env bash
printf '%s|%s\n' "\${CLAUDE_CONFIG_DIR:-DEFAULT}" "\$*" >> "${HOME}/claude.log"
exit 0
CL
  chmod +x "${HOME}/.local/bin/claude"
  _stub_agent bunx
  dybatpho::ensure_dir "${HOME}/Working/enterprise/U3T/.claude" > /dev/null
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${HOME}/.config/dyai/config.yaml" << CFG
global:
  skills: []
  mcp:
    filesystem:
      command: bunx
      args: ["@modelcontextprotocol/server-filesystem@2.0.0", "${HOME}/Working/personal", "${HOME}/Working/community"]
      env: {}
agents:
  claude: {}
CFG
  run bash "${HOOK}"
  assert_success
  # Default config: personal + community.
  grep '^DEFAULT|' "${HOME}/claude.log" | grep -q 'Working/personal'
  # Enterprise config dir: scoped to the enterprise tree, not personal/community.
  grep 'enterprise/U3T/.claude|' "${HOME}/claude.log" | grep -q 'Working/enterprise'
  run grep 'enterprise/U3T/.claude|' "${HOME}/claude.log"
  refute_output --partial 'Working/personal'
}

@test "a corrupt ~/.claude.json warns and the hook still processes other agents" {
  _stub_agent claude
  _stub_agent gemini
  printf 'not valid json{' > "${HOME}/.claude.json"
  _write_config
  run bash "${HOOK}"
  assert_success
  [[ "$(jq -r '.mcpServers.laya.command' "${HOME}/.gemini/settings.json")" == "${LAYA}" ]]
}

@test "a hyphenated MCP name registers into codex via the yq path, idempotently" {
  _stub_agent codex
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${HOME}/.config/dyai/config.yaml" << CFG
global:
  skills: []
  mcp:
    sequential-thinking:
      command: ${LAYA}
      args: []
      env: {}
agents:
  claude: {}
CFG
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.codex/config.toml"
  [[ "$(yq -p=toml -r '.mcp_servers."sequential-thinking".command' "${f}")" == "${LAYA}" ]]
  run bash "${HOOK}"
  assert_success
  refute_output --partial "Registered MCP sequential-thinking in ${f}"
}
