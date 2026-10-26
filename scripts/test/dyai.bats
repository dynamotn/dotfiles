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
  local before
  before="$(cat "${HOME}/.claude/agents/backend-developer.md")"
  dyai::setup_subagents
  [[ "$(cat "${HOME}/.claude/agents/backend-developer.md")" == "${before}" ]]
}

@test "dyai::setup_subagents honors a per-file include and an exclude list" {
  _stub claude
  local src="${BATS_TEST_TMPDIR}/volt2"
  mkdir -p "${src}/categories/01-core-development"
  for n in backend-developer electron-pro graphql-architect; do
    printf -- '---\nname: %s\n---\nx\n' "${n}" > "${src}/categories/01-core-development/${n}.md"
  done
  mkdir -p "${src}/categories/02-language-specialists"
  printf -- '---\nname: golang-pro\n---\nx\n' > "${src}/categories/02-language-specialists/golang-pro.md"
  eval 'dyai::fetch_repo() { printf "%s" "'"${src}"'"; }'
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${HOME}/.config/dyai/config.yaml" << 'CFG'
global:
  skills: []
  mcp: {}
  subagents:
    - repo: VoltAgent/awesome-claude-code-subagents
      ref: deadbeef
      include:
        - categories/01-core-development
        - categories/02-language-specialists/golang-pro.md
      exclude: [electron-pro, graphql-architect]
agents:
  claude: {}
CFG
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  # An earlier baseline installed both: graphql-architect untouched, and
  # electron-pro edited by the user afterwards.
  mkdir -p "${HOME}/.claude/agents"
  cp -- "${src}/categories/01-core-development/graphql-architect.md" "${HOME}/.claude/agents/"
  printf -- '---\nname: electron-pro\n---\nmine\n' > "${HOME}/.claude/agents/electron-pro.md"
  dyai::setup_subagents
  # category install minus the two excluded, plus the one file-include
  [ -f "${HOME}/.claude/agents/backend-developer.md" ]
  [ -f "${HOME}/.claude/agents/golang-pro.md" ]
  # The pinned copy of a now-excluded agent goes; the edited one stays.
  [ ! -f "${HOME}/.claude/agents/graphql-architect.md" ]
  grep -qx 'mine' "${HOME}/.claude/agents/electron-pro.md"
}

@test "dyai::setup_subagents converts each subagent into a Codex agent .toml, idempotent" {
  _stub codex
  local src="${BATS_TEST_TMPDIR}/volt3" dir="${BATS_TEST_TMPDIR}/volt3/categories/04"
  mkdir -p "${dir}"
  printf -- '---\nname: auditor\ndescription: "Audits: code"\ntools: Read, Grep, Glob\n---\nLine "one"\nline two\n' \
    > "${dir}/auditor.md"
  printf -- '---\nname: builder\ndescription: Builds\ntools: Read, Write, Bash\n---\nbuild\n' > "${dir}/builder.md"
  printf 'no frontmatter\n' > "${dir}/plain.md"
  eval 'dyai::fetch_repo() { printf "%s" "'"${src}"'"; }'
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  printf 'global:\n  subagents:\n    - {repo: o/r, ref: deadbeef, include: [categories/04]}\n' \
    > "${HOME}/.config/dyai/config.yaml"
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dyai::setup_subagents
  local a="${HOME}/.codex/agents/auditor.toml" b="${HOME}/.codex/agents/builder.toml"
  yq -p=toml -e '.name == "auditor" and .description == "Audits: code"' "${a}" > /dev/null
  yq -p=toml -e '.developer_instructions == "Line \"one\"\nline two"' "${a}" > /dev/null
  # No tool that writes, so the agent runs in a read-only sandbox.
  yq -p=toml -e '.sandbox_mode == "read-only"' "${a}" > /dev/null
  yq -p=toml -e 'has("sandbox_mode") | not' "${b}" > /dev/null
  [[ ! -e "${HOME}/.codex/agents/plain.toml" ]]
  cp "${a}" "${a}.before"
  dyai::setup_subagents
  cmp -s "${a}" "${a}.before"
}

@test "dyai::setup_installers runs a per-agent installer once, only for present agents" {
  _stub opencode
  # codex is intentionally NOT stubbed (its launcher is absent). Drop every
  # PATH entry holding a real codex too, or the test depends on the host.
  local dir keep="" parts
  IFS=: read -ra parts <<< "${PATH}"
  for dir in "${parts[@]}"; do
    [[ -x "${dir}/codex" ]] || keep+="${dir}:"
  done
  PATH="${keep%:}"
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${CONFIG_FILE}" << 'CFG'
global:
  installers:
    memtool:
      commands:
        opencode: "echo ran-opencode >> $HOME/inst.log"
        codex: "echo ran-codex >> $HOME/inst.log"
CFG
  dyai::setup_installers
  grep -qx 'ran-opencode' "${HOME}/inst.log"
  run grep -qx 'ran-codex' "${HOME}/inst.log"
  assert_failure
  # idempotent: a second run does not re-run (marker guards it)
  dyai::setup_installers
  [[ "$(grep -c 'ran-opencode' "${HOME}/inst.log")" == "1" ]]
}

@test "dyai::use materializes a preset's commands into ./.claude/commands; rm prunes" {
  _stub bunx
  local src="${BATS_TEST_TMPDIR}/cmds"
  mkdir -p "${src}/commands"
  printf -- '---\nname: deploy\n---\nrun deploy\n' > "${src}/commands/deploy.md"
  eval 'dyai::fetch_repo() { printf "%s" "'"${src}"'"; }'
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${CONFIG_FILE}" << 'CFG'
global:
  commands:
    - repo: owner/commands
      ref: deadbeef
      include: [commands]
registry:
  presets:
    ops:
      commands: [deploy]
CFG
  local proj="${BATS_TEST_TMPDIR}/cmdproj"
  mkdir -p "${proj}"
  git -C "${proj}" init -q
  (cd "${proj}" && dyai::use ops)
  [ -f "${proj}/.claude/commands/deploy.md" ]
  yq -p=toml '.materialized[]' "${proj}/.dyai.toml" | grep 'commands/deploy.md' > /dev/null
  run git -C "${proj}" check-ignore .claude/commands/deploy.md
  assert_success
  (cd "${proj}" && dyai::rm ops)
  [ ! -f "${proj}/.claude/commands/deploy.md" ]
}

@test "dyai::use registers a preset's mcp as Claude project-local; rm removes it" {
  _stub claude
  _stub bunx
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${CONFIG_FILE}" << 'CFG'
registry:
  presets:
    db:
      mcp:
        pg:
          command: uvx
          args: [postgres-mcp@0.3.0]
          env: {}
CFG
  local proj="${BATS_TEST_TMPDIR}/mcpproj"
  mkdir -p "${proj}"
  git -C "${proj}" init -q
  (cd "${proj}" && dyai::use db)
  grep -q 'STUB claude mcp add-json --scope local pg' "${HOME}/calls.log"
  yq -p=toml '.materialized_mcp[]' "${proj}/.dyai.toml" | grep -x 'pg' > /dev/null
  # idempotent: re-materialize does not re-add
  : > "${HOME}/calls.log"
  (cd "${proj}" && dyai::materialize)
  run grep -q 'add-json --scope local pg' "${HOME}/calls.log"
  assert_failure
  # rm removes the project-local server and clears the manifest
  (cd "${proj}" && dyai::rm db)
  grep -q 'STUB claude mcp remove --scope local pg' "${HOME}/calls.log"
  [[ "$(yq -p=toml '.materialized_mcp | length' "${proj}/.dyai.toml")" == "0" ]]
}

@test "dyai::use enables a preset's plugins in settings.local.json; rm drops only those" {
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${CONFIG_FILE}" << 'CFG'
agents:
  claude:
    plugins: [base@m]
    optional_plugins: [sec-a@m, sec-b@m]
registry:
  presets:
    sec:
      plugins: [sec-a@m, sec-b@m, ghost@m]
CFG
  local proj="${BATS_TEST_TMPDIR}/plugproj" f
  f="${proj}/.claude/settings.local.json"
  mkdir -p "${proj}/.claude"
  git -C "${proj}" init -q
  # The user's own local settings stay: a permission and a plugin they enabled.
  printf '{"permissions":{"allow":["Bash(ls)"]},"enabledPlugins":{"mine@m":true}}' > "${f}"
  # `run` must stay in this shell to capture output; every later path is absolute.
  cd "${proj}" || fail "cannot enter ${proj}"
  run dyai::use sec
  assert_success
  # A plugin no list installs is flagged and left alone.
  assert_output --partial 'plugin ghost@m is not in agents.claude.optional_plugins; not enabled'
  jq -e '.enabledPlugins == {"mine@m": true, "sec-a@m": true, "sec-b@m": true}' "${f}" > /dev/null
  jq -e '.permissions.allow == ["Bash(ls)"]' "${f}" > /dev/null
  yq -e -p=toml '.materialized_plugins | length == 2' "${proj}/.dyai.toml" > /dev/null
  grep -qxF '/.claude/settings.local.json' "${proj}/.git/info/exclude"
  local before
  before="$(< "${f}")"
  (cd "${proj}" && dyai::materialize)
  [[ "$(< "${f}")" == "${before}" ]] || fail "re-materialize changed ${f}"
  (cd "${proj}" && dyai::rm sec)
  jq -e '.enabledPlugins == {"mine@m": true}' "${f}" > /dev/null
  jq -e '.permissions.allow == ["Bash(ls)"]' "${f}" > /dev/null
  yq -e -p=toml '.materialized_plugins | length == 0' "${proj}/.dyai.toml" > /dev/null
}

@test "a crafted plugin manifest cannot drop a plugin the user's config does not name" {
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${CONFIG_FILE}" << 'CFG'
agents:
  claude:
    optional_plugins: [sec-a@m]
registry:
  presets:
    sec:
      plugins: [sec-a@m]
CFG
  local proj="${BATS_TEST_TMPDIR}/crafted" f
  f="${proj}/.claude/settings.local.json"
  mkdir -p "${proj}/.claude"
  git -C "${proj}" init -q
  printf '{"enabledPlugins":{"mine@m":true}}' > "${f}"
  # A cloned repository ships a manifest claiming dyai enabled mine@m.
  printf 'use = []\nmaterialized_plugins = ["mine@m"]\n' > "${proj}/.dyai.toml"
  (cd "${proj}" && dyai::materialize)
  jq -e '.enabledPlugins == {"mine@m": true}' "${f}" > /dev/null
}

@test "dyai::use does not record an mcp server whose registration failed; retries next run" {
  _stub bunx
  # a claude stub that FAILS `mcp add-json` but succeeds otherwise
  printf '#!/usr/bin/env bash\necho "STUB claude $*" >> "%s"\ncase "$*" in *add-json*) exit 1 ;; esac\nexit 0\n' \
    "${HOME}/calls.log" > "${HOME}/.local/bin/claude"
  chmod +x "${HOME}/.local/bin/claude"
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${CONFIG_FILE}" << 'CFG'
registry:
  presets:
    db:
      mcp:
        pg:
          command: uvx
          args: [postgres-mcp@0.3.0]
          env: {}
CFG
  local proj="${BATS_TEST_TMPDIR}/mcpfail"
  mkdir -p "${proj}"
  git -C "${proj}" init -q
  (cd "${proj}" && dyai::use db)
  # the add was attempted but failed, so it is NOT recorded as registered
  grep -q 'STUB claude mcp add-json --scope local pg' "${HOME}/calls.log"
  [[ "$(yq -p=toml '.materialized_mcp | length' "${proj}/.dyai.toml")" == "0" ]]
  # with a working claude, a re-materialize retries and now records it
  _stub claude
  : > "${HOME}/calls.log"
  (cd "${proj}" && dyai::materialize)
  grep -q 'STUB claude mcp add-json --scope local pg' "${HOME}/calls.log"
  yq -p=toml '.materialized_mcp[]' "${proj}/.dyai.toml" | grep -qx 'pg'
}

@test "dyai::use records a preset in .dyai.toml and personal-ignores it" {
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${CONFIG_FILE}" << 'CFG'
registry:
  languages:
    go: { subagents: [golang-pro], skills: [] }
CFG
  local proj="${BATS_TEST_TMPDIR}/proj"
  mkdir -p "${proj}"
  git -C "${proj}" init -q
  (cd "${proj}" && dyai::use go)
  yq -p=toml '.use[]' "${proj}/.dyai.toml" | grep -x 'go' > /dev/null
  grep -qxF '/.dyai.toml' "${proj}/.git/info/exclude"
  # idempotent: using again does not duplicate
  (cd "${proj}" && dyai::use go)
  [[ "$(yq -p=toml '.use | length' "${proj}/.dyai.toml")" == "1" ]]
}

@test "dyai::use errors on an unknown preset" {
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  printf 'registry:\n  languages:\n    go: {subagents: [golang-pro]}\n' > "${CONFIG_FILE}"
  local proj="${BATS_TEST_TMPDIR}/proj2"
  mkdir -p "${proj}"
  git -C "${proj}" init -q
  cd "${proj}"
  run dyai::use nope
  assert_failure
}

@test "dyai::use errors outside a git repository" {
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  printf 'registry:\n  languages:\n    go: {subagents: [golang-pro]}\n' > "${CONFIG_FILE}"
  local nonrepo="${BATS_TEST_TMPDIR}/plain"
  mkdir -p "${nonrepo}"
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
  local proj="${BATS_TEST_TMPDIR}/mproj"
  mkdir -p "${proj}"
  git -C "${proj}" init -q
  (cd "${proj}" && dyai::use go)
  [ -f "${proj}/.claude/agents/golang-pro.md" ]
  grep -q 'STUB bunx .* add owner/repo@golang-code-style' "${HOME}/calls.log"
  yq -p=toml '.materialized[]' "${proj}/.dyai.toml" | grep 'golang-pro.md' > /dev/null
  # idempotent: second run leaves the subagent unchanged
  local before
  before="$(cat "${proj}/.claude/agents/golang-pro.md")"
  (cd "${proj}" && dyai::materialize)
  [[ "$(cat "${proj}/.claude/agents/golang-pro.md")" == "${before}" ]]
}

@test "dyai::use materializes a skills-only preset with no subagent source" {
  _stub bunx
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${CONFIG_FILE}" << 'CFG'
registry:
  presets:
    security:
      skills:
        - owner/repo@threat-model
        - owner/repo@fuzzing
CFG
  local proj="${BATS_TEST_TMPDIR}/secproj"
  mkdir -p "${proj}"
  git -C "${proj}" init -q
  (cd "${proj}" && dyai::use security)
  grep -q 'STUB bunx .* add owner/repo@threat-model' "${HOME}/calls.log"
  grep -q 'STUB bunx .* add owner/repo@fuzzing' "${HOME}/calls.log"
  yq -p=toml '.materialized[]' "${proj}/.dyai.toml" | grep 'threat-model' > /dev/null
  run git -C "${proj}" check-ignore .agents/skills/threat-model
  assert_success
  # a skills-only preset creates no subagents dir
  [ ! -d "${proj}/.claude/agents" ]
}

@test "dyai::materialize installs every skill even when the skills CLI reads stdin" {
  # The real skills CLI drains stdin; it must not swallow the rest of the list.
  printf '#!/usr/bin/env bash\ncat > /dev/null\necho "STUB bunx $*" >> "%s"\n' "${HOME}/calls.log" \
    > "${HOME}/.local/bin/bunx"
  chmod +x "${HOME}/.local/bin/bunx"
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${CONFIG_FILE}" << 'CFG'
registry:
  presets:
    security:
      skills:
        - owner/repo@threat-model
        - owner/repo@fuzzing
CFG
  local proj="${BATS_TEST_TMPDIR}/stdinproj"
  mkdir -p "${proj}"
  git -C "${proj}" init -q
  (cd "${proj}" && dyai::use security)
  grep -q 'STUB bunx .* add owner/repo@threat-model' "${HOME}/calls.log"
  grep -q 'STUB bunx .* add owner/repo@fuzzing' "${HOME}/calls.log"
}

@test "dyai::materialize tracks a skill given as a pinned GitHub tree URL" {
  _stub bunx
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${CONFIG_FILE}" << 'CFG'
registry:
  presets:
    thinking:
      skills:
        - https://github.com/owner/repo/tree/deadbeef/skills/FirstPrinciples
CFG
  local proj="${BATS_TEST_TMPDIR}/urlproj"
  mkdir -p "${proj}"
  git -C "${proj}" init -q
  (cd "${proj}" && dyai::use thinking)
  grep -q 'STUB bunx .* add https://github.com/owner/repo/tree/deadbeef/skills/FirstPrinciples' "${HOME}/calls.log"
  # The skills CLI installs a URL skill under its lowercased last path segment.
  yq -p=toml '.materialized[]' "${proj}/.dyai.toml" | grep -x "${proj}/.agents/skills/firstprinciples" > /dev/null
  # Once that dir exists, a re-run does not reinstall it.
  mkdir -p "${proj}/.agents/skills/firstprinciples"
  : > "${HOME}/calls.log"
  (cd "${proj}" && dyai::materialize)
  run grep -q 'STUB bunx' "${HOME}/calls.log"
  assert_failure
}

@test "dyai::use personal-ignores the materialized subagent, not only .dyai.toml" {
  _stub claude
  _stub bunx
  local src="${BATS_TEST_TMPDIR}/igvolt"
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
    go: { subagents: [golang-pro] }
CFG
  local proj="${BATS_TEST_TMPDIR}/igproj"
  mkdir -p "${proj}"
  git -C "${proj}" init -q
  (cd "${proj}" && dyai::use go)
  run git -C "${proj}" check-ignore .claude/agents/golang-pro.md
  assert_success
}

@test "dyai::use works when .git/info does not exist yet" {
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  printf 'registry:\n  languages:\n    go: {subagents: [], skills: []}\n' > "${CONFIG_FILE}"
  local proj="${BATS_TEST_TMPDIR}/noinfo"
  mkdir -p "${proj}"
  git -C "${proj}" init -q
  # Some git versions / templates do not create .git/info on init.
  rm -rf "${proj}/.git/info"
  (cd "${proj}" && dyai::use go)
  [ -f "${proj}/.dyai.toml" ]
  run git -C "${proj}" check-ignore .dyai.toml
  assert_success
}

@test "dyai::use excludes .dyai.toml correctly inside a git worktree" {
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  # a preset with nothing to materialize, so no fetch is needed
  printf 'registry:\n  languages:\n    go: {subagents: [], skills: []}\n' > "${CONFIG_FILE}"
  local proj="${BATS_TEST_TMPDIR}/wtmain"
  mkdir -p "${proj}"
  git -C "${proj}" init -q
  git -C "${proj}" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  local wt="${BATS_TEST_TMPDIR}/wtlinked"
  git -C "${proj}" worktree add -q "${wt}" -b wt
  (cd "${wt}" && dyai::use go)
  [ -f "${wt}/.dyai.toml" ]
  run git -C "${wt}" check-ignore .dyai.toml
  assert_success
}

@test "dyai::materialize leaves still-wanted subagents when a required fetch fails" {
  _stub claude
  _stub bunx
  local src="${BATS_TEST_TMPDIR}/okvolt"
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
    go:     { subagents: [golang-pro] }
    python: { subagents: [python-pro] }
CFG
  local proj="${BATS_TEST_TMPDIR}/failproj"
  mkdir -p "${proj}"
  git -C "${proj}" init -q
  (cd "${proj}" && dyai::use go)
  [ -f "${proj}/.claude/agents/golang-pro.md" ]
  # now the source is unreachable; opting into python must NOT delete golang-pro
  eval 'dyai::fetch_repo() { return 1; }'
  cd "${proj}"
  run dyai::use python
  assert_failure
  [ -f "${proj}/.claude/agents/golang-pro.md" ]
  yq -p=toml '.materialized[]' "${proj}/.dyai.toml" | grep 'golang-pro.md' > /dev/null
}

@test "dyai::ls shows the global baseline and this project's presets" {
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${CONFIG_FILE}" << EOF
global:
  skills:
    - owner/repo@alpha
  mcp:
    laya:
      command: ${LAYA}
registry:
  languages:
    go: { subagents: [golang-pro] }
EOF
  local proj="${BATS_TEST_TMPDIR}/lsproj"
  mkdir -p "${proj}"
  git -C "${proj}" init -q
  : > "${proj}/.dyai.toml"
  N=go yq -p=toml -o=toml -i '.use = [strenv(N)]' "${proj}/.dyai.toml"
  cd "${proj}"
  run dyai::ls
  assert_success
  assert_output --partial "skills: 1"
  assert_output --partial "laya"
  assert_output --partial "go"
}

@test "dyai::rm drops a preset and prunes the files it materialized" {
  _stub claude
  _stub bunx
  local src="${BATS_TEST_TMPDIR}/rmvolt"
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
    go: { subagents: [golang-pro] }
CFG
  local proj="${BATS_TEST_TMPDIR}/rmproj"
  mkdir -p "${proj}"
  git -C "${proj}" init -q
  (cd "${proj}" && dyai::use go)
  [ -f "${proj}/.claude/agents/golang-pro.md" ]
  (cd "${proj}" && dyai::rm go)
  [ ! -f "${proj}/.claude/agents/golang-pro.md" ]
  [[ "$(yq -p=toml '.use | length' "${proj}/.dyai.toml")" == "0" ]]
}

@test "dyai::prune_and_record refuses to delete outside the project subtrees" {
  local proj="${BATS_TEST_TMPDIR}/trav"
  mkdir -p "${proj}/.claude/agents"
  local victim="${BATS_TEST_TMPDIR}/victim"
  mkdir -p "${victim}"
  : > "${victim}/keep"
  local toml="${proj}/.dyai.toml"
  # a manifest crafted to escape the project via .. and to name a path
  # outside the two subtrees dyai writes
  printf 'materialized = ["%s/../victim/keep", "%s/.ssh/id_ed25519", "%s/.claude/agents/stale.md"]\n' \
    "${proj}" "${proj}" "${proj}" > "${toml}"
  : > "${proj}/.claude/agents/stale.md"
  # desired is empty, so every manifest entry is a prune candidate
  dyai::prune_and_record "${toml}"
  # the escape and the out-of-subtree path survive; only the real subtree file is pruned
  [ -f "${victim}/keep" ]
  [ ! -f "${proj}/.claude/agents/stale.md" ]
}

@test "dyai::rm errors on a preset the project does not use" {
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  printf 'registry:\n  languages:\n    go: {subagents: [golang-pro]}\n' > "${CONFIG_FILE}"
  local proj="${BATS_TEST_TMPDIR}/rmempty"
  mkdir -p "${proj}"
  git -C "${proj}" init -q
  : > "${proj}/.dyai.toml"
  cd "${proj}"
  run dyai::rm go
  assert_failure
}

@test "dyai::rm keeps a file another active preset still materializes" {
  _stub claude
  _stub bunx
  local src="${BATS_TEST_TMPDIR}/shvolt"
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
    go:   { subagents: [golang-pro] }
  presets:
    svc:  { subagents: [golang-pro] }
CFG
  local proj="${BATS_TEST_TMPDIR}/shproj"
  mkdir -p "${proj}"
  git -C "${proj}" init -q
  (cd "${proj}" && dyai::use go && dyai::use svc)
  (cd "${proj}" && dyai::rm go)
  [ -f "${proj}/.claude/agents/golang-pro.md" ]
}

@test "dyai::install runs the LSP step before marketplaces/plugins and tolerates a failing nvim export" {
  _stub claude
  _stub bunx
  _stub gemini
  # a failing nvim stub exercises dyai_lsp::export's failure path; it must not
  # abort dyai::install or the plugin install that follows
  printf '#!/usr/bin/env bash\nexit 1\n' > "${HOME}/.local/bin/nvim"
  chmod +x "${HOME}/.local/bin/nvim"
  # The real machine has uvx/codex/gemini/agy on PATH outside the sandbox bin
  # (mise shims, bun bin, ~/.local/bin); restrict PATH to the sandbox bin plus
  # the system dirs jq/yq/coreutils actually live in, so serena's setup finds
  # none of those real launchers and skips instead of touching the network or
  # the real user's agent configs.
  # shellcheck disable=SC2312 # jq/yq are always on this test runner's real PATH
  ln -s "$(command -v jq)" "${HOME}/.local/bin/jq"
  # shellcheck disable=SC2312 # jq/yq are always on this test runner's real PATH
  ln -s "$(command -v yq)" "${HOME}/.local/bin/yq"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${HOME}/.config/dyai/config.yaml" << 'CFG'
global:
  skills: []
  mcp: {}
agents:
  claude:
    plugins:
      - dyai-lsp@dyai-lsp
CFG
  PATH="${HOME}/.local/bin:/usr/bin:/bin" run dyai::install
  assert_success
  grep -q 'STUB claude plugin marketplace add' "${HOME}/calls.log"
  grep -q 'STUB claude plugin install dyai-lsp@dyai-lsp' "${HOME}/calls.log"
  local market_line plugin_line
  # shellcheck disable=SC2312 # a missing match yields an empty line number, which fails the final compare
  market_line="$(grep -n 'STUB claude plugin marketplace add' "${HOME}/calls.log" | head -1 | cut -d: -f1)"
  # shellcheck disable=SC2312 # a missing match yields an empty line number, which fails the final compare
  plugin_line="$(grep -n 'STUB claude plugin install dyai-lsp@dyai-lsp' "${HOME}/calls.log" | head -1 | cut -d: -f1)"
  [[ "${market_line}" -lt "${plugin_line}" ]]
}

@test "dyai::mcp_bunx_env gives bunx servers a persistent TMPDIR and leaves the rest alone" {
  run dyai::mcp_bunx_env '{"command":"bunx","args":["pkg@1"],"env":{}}'
  assert_success
  run jq -r '.env.TMPDIR' <<< "${output}"
  assert_output "${HOME}/.cache/bunx"
  run dyai::mcp_bunx_env '{"command":"bunx","env":{"TMPDIR":"/keep"}}'
  run jq -r '.env.TMPDIR' <<< "${output}"
  assert_output /keep
  run dyai::mcp_bunx_env '{"command":"uvx","args":[]}'
  run jq -c '.env' <<< "${output}"
  assert_output null
}

@test "a skill install that exits 0 but writes nothing is reported" {
  _stub bunx
  _write_config
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  SKILLS_DIR="${HOME}/.agents/skills"
  run dyai::setup_skills
  assert_success
  assert_output --partial "installer reported success but ${SKILLS_DIR}/alpha is missing"
  [[ ! -e "${HOME}/.cache/dyai/installed/skills/alpha.sha256" ]]
}

@test "a verified skill install records its hash" {
  printf '#!/usr/bin/env bash\nmkdir -p "%s/.agents/skills/alpha" && echo x > "%s/.agents/skills/alpha/SKILL.md"\n' \
    "${HOME}" "${HOME}" > "${HOME}/.local/bin/bunx"
  chmod +x "${HOME}/.local/bin/bunx"
  _write_config
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  SKILLS_DIR="${HOME}/.agents/skills"
  dyai::setup_skills
  [[ -s "${HOME}/.cache/dyai/installed/skills/alpha.sha256" ]]
}

@test "a hanging installer is cut off and install continues" {
  _stub opencode
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${CONFIG_FILE}" << 'CFG'
global:
  installers:
    a-hang:
      commands:
        opencode: "sleep 30"
    b-ok:
      commands:
        opencode: "echo ran >> $HOME/inst.log"
CFG
  DYAI_EXTERNAL_TIMEOUT=1 run dyai::setup_installers
  assert_success
  assert_output --partial "installer a-hang for opencode failed"
  grep -qx 'ran' "${HOME}/inst.log"
}

@test "an installer reading stdin gets EOF" {
  _stub opencode
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${CONFIG_FILE}" << 'CFG'
global:
  installers:
    reader:
      commands:
        opencode: "read -r x || echo eof >> $HOME/inst.log"
CFG
  DYAI_EXTERNAL_TIMEOUT=5 dyai::setup_installers
  grep -qx 'eof' "${HOME}/inst.log"
}

# Point setup_subagents at a one-agent fixture source; sets PINNED to the pinned file.
function _subagent_fixture {
  local src="${BATS_TEST_TMPDIR}/voltlocal"
  mkdir -p "${src}/categories/01-core-development"
  printf -- '---\nname: backend-developer\nmodel: sonnet\n---\nv1\n' \
    > "${src}/categories/01-core-development/backend-developer.md"
  eval 'dyai::fetch_repo() { printf "%s" "'"${src}"'"; }'
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${HOME}/.config/dyai/config.yaml" << 'CFG'
global:
  subagents:
    - repo: VoltAgent/awesome-claude-code-subagents
      ref: deadbeef
      include: [categories/01-core-development]
agents:
  claude: {}
CFG
  CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
  PINNED="${src}/categories/01-core-development/backend-developer.md"
}

@test "an edited subagent survives a changed upstream" {
  _stub claude
  local dest="${HOME}/.claude/agents/backend-developer.md"
  _subagent_fixture
  dyai::setup_subagents
  printf 'my note\n' >> "${dest}"
  printf -- '---\nname: backend-developer\n---\nv2\n' > "${PINNED}"
  run dyai::setup_subagents
  assert_success
  assert_output --partial "LOCAL EDITS kept"
  grep -qx 'my note' "${dest}"
}

@test "an untouched subagent follows upstream" {
  _stub claude
  local dest="${HOME}/.claude/agents/backend-developer.md"
  _subagent_fixture
  dyai::setup_subagents
  printf -- '---\nname: backend-developer\n---\nv2\n' > "${PINNED}"
  run dyai::setup_subagents
  refute_output --partial "LOCAL EDITS"
  cmp -s "${PINNED}" "${dest}"
}

@test "a subagent installed before hashes existed is replaced once" {
  _stub claude
  local dest="${HOME}/.claude/agents/backend-developer.md"
  _subagent_fixture
  mkdir -p "${HOME}/.claude/agents"
  printf 'old copy\n' > "${dest}"
  dyai::setup_subagents
  cmp -s "${PINNED}" "${dest}"
  [[ -s "${HOME}/.cache/dyai/installed/subagents/backend-developer.sha256" ]]
}

@test "dir_hash changes when a file is renamed" {
  local d="${BATS_TEST_TMPDIR}/h"
  mkdir -p "${d}"
  echo x > "${d}/a"
  local before after
  before="$(dyai::dir_hash "${d}")"
  mv "${d}/a" "${d}/b"
  after="$(dyai::dir_hash "${d}")"
  [[ "${after}" != "${before}" ]]
}
