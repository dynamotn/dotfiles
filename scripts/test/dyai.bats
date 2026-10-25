setup() {
  load test_helper
  setup_dotfiles_test_env
  # The library defines functions only; paths resolve from ${HOME} at call time,
  # so sourcing after the sandbox HOME is set is correct.
  . "${DOTFILES_DIR}/scripts/lib/dyai.sh"
  LAYA="${HOME}/.local/bin/laya-mcp-server"
  : > "${LAYA}" && chmod +x "${LAYA}"
}

function _stub {
  printf '#!/usr/bin/env bash\necho "STUB $(basename "$0") $*" >> "%s"\nexit 0\n' "${HOME}/calls.log" > "${HOME}/.local/bin/${1}"
  chmod +x "${HOME}/.local/bin/${1}"
}

function _write_config {
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${HOME}/.config/dyai/config.yaml" << EOF
global:
  skills:
    - owner/repo@alpha
  mcp:
    laya:
      command: ${LAYA}
      args: []
      env: {}
agents:
  claude:
    marketplaces:
      mk-one: { source: { source: github, repo: owner/mk-one } }
    plugins:
      - alpha@mk-one
EOF
}

@test "dyai::install installs marketplaces, plugins, skills and registers laya" {
  _stub claude
  _stub bunx
  _stub gemini
  _write_config
  dyai::install
  grep -q 'STUB claude plugin marketplace add owner/mk-one' "${HOME}/calls.log"
  grep -q 'STUB claude plugin install alpha@mk-one' "${HOME}/calls.log"
  grep -q 'STUB bunx .* add owner/repo@alpha -g -y' "${HOME}/calls.log"
  grep -q 'STUB claude mcp add-json --scope user laya' "${HOME}/calls.log"
  [[ "$(jq -r '.mcpServers.laya.command' "${HOME}/.gemini/settings.json")" == "${LAYA}" ]]
}

@test "dyai::install warns and skips when the dyai config is missing" {
  _stub claude
  run dyai::install
  assert_success
  assert_output --partial "dyai config not found"
}

@test "dyai --help lists the install subcommand" {
  render_template "home/dot_local/bin/executable_dyai.tmpl" "${BATS_TEST_TMPDIR}/dyai"
  run bash "${BATS_TEST_TMPDIR}/dyai" --help
  assert_success
  assert_output --partial "install"
}

@test "dyai install runs the global setup" {
  _stub claude
  _stub bunx
  _stub gemini
  _write_config
  render_template "home/dot_local/bin/executable_dyai.tmpl" "${BATS_TEST_TMPDIR}/dyai"
  run bash "${BATS_TEST_TMPDIR}/dyai" install
  assert_success
  grep -q 'STUB claude mcp add-json --scope user laya' "${HOME}/calls.log"
}
