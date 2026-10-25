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

@test "dyai::setup_subagents copies category .md into ~/.claude/agents, skips README, idempotent" {
  _stub claude
  local src="${BATS_TEST_TMPDIR}/voltsrc"
  mkdir -p "${src}/categories/01-core-development"
  printf -- '---\nname: backend-developer\n---\nbody\n' > "${src}/categories/01-core-development/backend-developer.md"
  printf '# readme\n' > "${src}/categories/01-core-development/README.md"
  # stub the network fetch to return the fixture
  eval 'dyai::fetch_repo() { printf "%s" "'"${src}"'"; }'
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${HOME}/.config/dyai/config.yaml" << 'CFG'
global:
  skills: []
  mcp: {}
  subagents:
    - repo: VoltAgent/awesome-claude-code-subagents
      ref: deadbeef
      include: [categories/01-core-development]
agents:
  claude: {}
CFG
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.claude/agents" > /dev/null
  printf 'mine\n' > "${HOME}/.claude/agents/mine.md"
  dyai::setup_subagents
  [ -f "${HOME}/.claude/agents/backend-developer.md" ]
  [ ! -f "${HOME}/.claude/agents/README.md" ]
  [ -f "${HOME}/.claude/agents/mine.md" ]
  local before; before="$(cat "${HOME}/.claude/agents/backend-developer.md")"
  dyai::setup_subagents
  [[ "$(cat "${HOME}/.claude/agents/backend-developer.md")" == "${before}" ]]
}

@test "dyai::use records a preset in .dyai.toml and personal-ignores it" {
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${CONFIG_FILE}" << 'CFG'
registry:
  languages:
    go: { subagents: [golang-pro], skills: [] }
CFG
  local proj="${BATS_TEST_TMPDIR}/proj"; mkdir -p "${proj}"; git -C "${proj}" init -q
  ( cd "${proj}" && dyai::use go )
  yq -p=toml '.use[]' "${proj}/.dyai.toml" | grep -qx 'go'
  grep -qxF '.dyai.toml' "${proj}/.git/info/exclude"
  # idempotent: using again does not duplicate
  ( cd "${proj}" && dyai::use go )
  [[ "$(yq -p=toml '.use | length' "${proj}/.dyai.toml")" == "1" ]]
}

@test "dyai::use errors on an unknown preset" {
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  printf 'registry:\n  languages:\n    go: {subagents: [golang-pro]}\n' > "${CONFIG_FILE}"
  local proj="${BATS_TEST_TMPDIR}/proj2"; mkdir -p "${proj}"; git -C "${proj}" init -q
  cd "${proj}"
  run dyai::use nope
  assert_failure
}

@test "dyai::use errors outside a git repository" {
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  printf 'registry:\n  languages:\n    go: {subagents: [golang-pro]}\n' > "${CONFIG_FILE}"
  local nonrepo="${BATS_TEST_TMPDIR}/plain"; mkdir -p "${nonrepo}"
  cd "${nonrepo}"
  run dyai::use go
  assert_failure
}

@test "dyai::use materializes a preset's subagents and skills into the project" {
  _stub claude
  _stub bunx
  local src="${BATS_TEST_TMPDIR}/volt"
  mkdir -p "${src}/categories/02-language-specialists"
  printf -- '---\nname: golang-pro\n---\nx\n' > "${src}/categories/02-language-specialists/golang-pro.md"
  eval 'dyai::fetch_repo() { printf "%s" "'"${src}"'"; }'
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${CONFIG_FILE}" << 'CFG'
global:
  subagents:
    - repo: VoltAgent/awesome-claude-code-subagents
      ref: deadbeef
      include: [categories/02-language-specialists]
registry:
  languages:
    go: { subagents: [golang-pro], skills: [owner/repo@golang-code-style] }
CFG
  local proj="${BATS_TEST_TMPDIR}/mproj"; mkdir -p "${proj}"; git -C "${proj}" init -q
  ( cd "${proj}" && dyai::use go )
  [ -f "${proj}/.claude/agents/golang-pro.md" ]
  grep -q 'STUB bunx .* add owner/repo@golang-code-style' "${HOME}/calls.log"
  yq -p=toml '.materialized[]' "${proj}/.dyai.toml" | grep -q 'golang-pro.md'
  # idempotent: second run leaves the subagent unchanged
  local before; before="$(cat "${proj}/.claude/agents/golang-pro.md")"
  ( cd "${proj}" && dyai::materialize )
  [[ "$(cat "${proj}/.claude/agents/golang-pro.md")" == "${before}" ]]
}
