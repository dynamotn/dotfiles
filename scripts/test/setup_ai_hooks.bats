setup() {
  load test_helper
  setup_dotfiles_test_env
  HOOK="${BATS_TEST_TMPDIR}/setup-ai.sh"
  render_template "home/.chezmoiscripts/run_onchange_after_03-setup-ai.sh.tmpl" "${HOOK}"
}

function _stub_agent {
  printf '#!/usr/bin/env bash\nexit 0\n' > "${HOME}/.local/bin/${1}"
  chmod +x "${HOME}/.local/bin/${1}"
}

# Config with notify hooks but no MCP server, to isolate hook behavior.
function _write_config {
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${HOME}/.config/dyai/config.yaml" << 'EOF'
global:
  skills: []
  mcp: {}
  hooks:
    stop:
      event: stop
      run: "notify-send 'AI agent' 'Task finished!'; true"
    input:
      event: input
      run: "notify-send 'AI agent' 'Waiting for your input!'; true"
agents:
  claude: {}
EOF
}

@test "gemini: notify hooks land in AfterAgent/Notification, unrelated hook survives, idempotent" {
  _stub_agent gemini
  dybatpho::ensure_dir "${HOME}/.gemini" > /dev/null
  printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo hi"}]}]}}' \
    > "${HOME}/.gemini/settings.json"
  _write_config
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.gemini/settings.json"
  jq -e '.hooks.AfterAgent[0].hooks[0].command | test("notify-send")' "${f}" > /dev/null
  jq -e '.hooks.Notification[0].hooks[0].command | test("notify-send")' "${f}" > /dev/null
  [[ "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "${f}")" == "echo hi" ]]
  local before
  before="$(cat "${f}")"
  run bash "${HOOK}"
  assert_success
  [[ "$(cat "${f}")" == "${before}" ]]
}

@test "gemini: an old dyai notify hook in SessionEnd moves to AfterAgent, others stay" {
  _stub_agent gemini
  dybatpho::ensure_dir "${HOME}/.gemini" > /dev/null
  cat > "${HOME}/.gemini/settings.json" << 'EOF'
{"hooks":{"SessionEnd":[
  {"hooks":[{"type":"command","command":"old","name":"dyai-notify"}]},
  {"hooks":[{"type":"command","command":"mine"}]}]}}
EOF
  _write_config
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.gemini/settings.json"
  jq -e '[.hooks.SessionEnd[].hooks[0].command] == ["mine"]' "${f}" > /dev/null
  jq -e '.hooks.AfterAgent | length == 1' "${f}" > /dev/null
  printf '{"hooks":{"SessionEnd":[{"hooks":[{"type":"command","command":"old","name":"dyai-notify"}]}]}}' \
    > "${f}"
  run bash "${HOOK}"
  assert_success
  jq -e '.hooks | has("SessionEnd") | not' "${f}" > /dev/null
}

@test "copilot: notify hooks written to its dedicated hooks file" {
  _stub_agent copilot
  _write_config
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.copilot/hooks/dyai.json"
  [[ "$(jq -r '.version' "${f}")" == "1" ]]
  jq -e '.hooks.agentStop[0].bash | test("notify-send")' "${f}" > /dev/null
  jq -e '.hooks.notification[0].bash | test("notify-send")' "${f}" > /dev/null
}

@test "codex: notify hooks written as matcher groups Codex can load" {
  _stub_agent codex
  _write_config
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.codex/config.toml"
  yq -p=toml -e '.hooks.Stop[0].hooks[0].command | test("notify-send")' "${f}" > /dev/null
  yq -p=toml -e '.hooks.PermissionRequest[0].hooks[0].command | test("notify-send")' "${f}" > /dev/null
  yq -p=toml -e '.hooks.Stop[0].hooks[0].type == "command"' "${f}" > /dev/null
  cp "${f}" "${f}.before"
  run bash "${HOOK}"
  assert_success
  cmp -s "${f}" "${f}.before"
}

@test "codex: the old map-shaped hooks are replaced" {
  _stub_agent codex
  _write_config
  local f="${HOME}/.codex/config.toml"
  mkdir -p "${HOME}/.codex"
  printf '[hooks.Stop]\nhooks = [{ command = "old" }]\n' > "${f}"
  printf '[hooks.Notification]\nhooks = [{ command = "old" }]\n' >> "${f}"
  run bash "${HOOK}"
  assert_success
  yq -p=toml -e '.hooks.Stop | type == "!!seq"' "${f}" > /dev/null
  yq -p=toml -e '.hooks | has("Notification") | not' "${f}" > /dev/null
}

@test "no hook config is written for agy or opencode" {
  _stub_agent agy
  _stub_agent opencode
  _write_config
  run bash "${HOOK}"
  assert_success
  [ ! -f "${HOME}/.gemini/config/hooks.json" ]
  # opencode.json, if present, carries no hooks key.
  if [ -f "${HOME}/.config/opencode/opencode.json" ]; then
    [[ "$(jq -r '.hooks // "none"' "${HOME}/.config/opencode/opencode.json")" == "none" ]]
  fi
}

@test "policy.guard wires dyai-guard into gemini, copilot and codex, idempotently" {
  _stub_agent gemini
  _stub_agent copilot
  _stub_agent codex
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  # dyshellint disable=SC2088 the glob is text for dyai, which reads ~ itself
  printf 'global:\n  skills: []\n  mcp: {}\n  policy:\n    guard: true\n    permissions:\n      deny:\n        - "Read(~/.ssh/**)"\n        - "Bash(age -d *)"\nagents:\n  claude: {}\n' \
    > "${HOME}/.config/dyai/config.yaml"
  run bash "${HOOK}"
  assert_success
  # The Read denies, for dyai-guard to hold in the shell of the agents
  # that cannot hold a path rule.
  run cat "${HOME}/.config/dyai/guard-deny-read"
  assert_output '~/.ssh/**'
  local gemini="${HOME}/.gemini/settings.json" copilot="${HOME}/.copilot/hooks/dyai-guard.json"
  local codex="${HOME}/.codex/config.toml"
  jq -e '.hooks.BeforeTool == [{matcher: "run_shell_command",
    hooks: [{type: "command", command: "dyai-guard gemini", name: "dyai-guard"}]}]' "${gemini}" > /dev/null
  jq -e '.hooks.preToolUse == [{type: "command", matcher: "bash", bash: "dyai-guard copilot"}]' \
    "${copilot}" > /dev/null
  local pre before after
  # Key order is the TOML writer's, not part of the rule.
  pre="$(yq -p=toml -o=json -I=0 '.hooks.PreToolUse' "${codex}" | jq -cS .)"
  assert_equal "${pre}" "$(jq -cS . <<< '[{"matcher":"^Bash$","hooks":[{"type":"command","command":"dyai-guard codex"}]}]')"
  before="$(cat "${gemini}" "${copilot}" "${codex}")"
  run bash "${HOOK}"
  assert_success
  after="$(cat "${gemini}" "${copilot}" "${codex}")"
  assert_equal "${after}" "${before}"
}

@test "without policy.guard no agent gets the dyai-guard hook" {
  _stub_agent gemini
  _write_config
  run bash "${HOOK}"
  assert_success
  jq -e '.hooks.BeforeTool == null' "${HOME}/.gemini/settings.json" > /dev/null
}
