# dyshellint disable=SC2154 DOTFILES_DIR, HOME and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/dyai.sh"
  # Only the stubs and the system tools: a real agent CLI on the host must not
  # turn into drift lines here. jq and yq are linked one by one: their own
  # directory (often ~/.local/bin) may hold real agent CLIs too.
  local tools="${BATS_TEST_TMPDIR}/tools" jq_bin yq_bin
  jq_bin="$(command -v jq)"
  yq_bin="$(command -v yq)"
  mkdir -p "${tools}"
  ln -s "${jq_bin}" "${tools}/jq"
  ln -s "${yq_bin}" "${tools}/yq"
  FULL_PATH="${PATH}"
  PATH="${HOME}/.local/bin:${tools}:/usr/bin:/bin"
  LAYA="${HOME}/.local/bin/laya-mcp-server"
  : > "${LAYA}" && chmod +x "${LAYA}"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${HOME}/.local/bin/claude"
  chmod +x "${HOME}/.local/bin/claude"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${HOME}/.config/dyai/config.yaml" << EOF
global:
  skills: [owner/repo@alpha]
  mcp:
    laya: { command: ${LAYA}, args: [], env: {} }
agents:
  claude:
    plugins: [beta@mk-one]
EOF
}

# Make the machine match the config above.
function _arm {
  mkdir -p "${HOME}/.agents/skills/alpha" "${HOME}/.claude/plugins"
  echo skill > "${HOME}/.agents/skills/alpha/SKILL.md"
  local hash
  hash="$(dyai::dir_hash "${HOME}/.agents/skills/alpha")"
  dyai::installed_hash skills alpha "${hash}"
  printf '{"plugins":{"beta@mk-one":[]}}\n' > "${HOME}/.claude/plugins/installed_plugins.json"
  printf '{"mcpServers":{"laya":{"command":"%s"}}}\n' "${LAYA}" > "${HOME}/.claude.json"
}

@test "status is silent on an armed machine" {
  _arm
  run dyai_status::main true
  assert_success
  assert_output ""
}

@test "status names a missing skill" {
  _arm
  rm -rf "${HOME}/.agents/skills/alpha"
  run dyai_status::main true
  assert_failure
  assert_output --partial "all skill alpha: missing"
}

@test "status names a locally edited skill" {
  _arm
  echo mine >> "${HOME}/.agents/skills/alpha/SKILL.md"
  run dyai_status::main true
  assert_failure
  assert_output --partial "all skill alpha: LOCAL EDITS"
}

@test "status names a missing plugin and an unregistered MCP server" {
  _arm
  printf '{"plugins":{}}\n' > "${HOME}/.claude/plugins/installed_plugins.json"
  printf '{}\n' > "${HOME}/.claude.json"
  run dyai_status::main true
  assert_failure
  assert_output --partial "claude plugin beta@mk-one: missing"
  assert_output --partial "claude mcp laya: not registered"
}

@test "status names a locally edited subagent" {
  _arm
  mkdir -p "${HOME}/.claude/agents"
  echo pinned > "${HOME}/.claude/agents/helper.md"
  local hash
  hash="$(dyai::dir_hash "${HOME}/.claude/agents/helper.md")"
  dyai::installed_hash subagents helper "${hash}"
  echo mine >> "${HOME}/.claude/agents/helper.md"
  run dyai_status::main true
  assert_failure
  assert_output --partial "claude subagent helper: LOCAL EDITS"
}

@test "status checks an installed agent and skips the rest" {
  _arm
  printf '#!/usr/bin/env bash\nexit 0\n' > "${HOME}/.local/bin/gemini"
  chmod +x "${HOME}/.local/bin/gemini"
  run dyai_status::main true
  assert_failure
  assert_output --partial "gemini mcp laya: not in"
  refute_output --partial "codex"
  refute_output --partial "opencode"
}

@test "status without quiet prints a summary" {
  _arm
  run dyai_status::main false
  assert_success
  assert_output "dyai: every agent matches the config"
}

@test "dyai status --quiet runs from the CLI" {
  _arm
  PATH="${FULL_PATH}" render_template "home/dot_local/bin/executable_dyai.tmpl" "${BATS_TEST_TMPDIR}/dyai"
  run bash "${BATS_TEST_TMPDIR}/dyai" status --quiet
  assert_success
  assert_output ""
}

@test "status quiet finishes under 2 seconds" {
  _arm
  # SECONDS counts whole seconds and would let almost 3 s through.
  local start elapsed_ms
  start="$(date +%s%N)"
  dyai_status::main true
  elapsed_ms=$((($(date +%s%N) - start) / 1000000))
  ((elapsed_ms < 2000)) || fail "status --quiet took ${elapsed_ms} ms"
}
