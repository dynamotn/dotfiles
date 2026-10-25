setup() {
  load test_helper
  setup_dotfiles_test_env
  # shellcheck disable=SC2154 # DOTFILES_DIR is set by test_helper.bash
  . "${DOTFILES_DIR}/scripts/lib/dyai.sh"
  export XDG_CACHE_HOME="${HOME}/.cache"
  export XDG_DATA_HOME="${HOME}/.local/share"
  FIXTURES="${DOTFILES_DIR}/scripts/test/fixtures/dyai-lsp"
  export DYAI_NVIM_CONFIG="${FIXTURES}/nvim"
  export DYAI_LSPCONFIG_DIR="${FIXTURES}/lspconfig"
  # shellcheck disable=SC2154 # BATS_TEST_TMPDIR is set by bats itself
  export DYAI_MASON_BIN="${BATS_TEST_TMPDIR}/mason_bin"
  mkdir -p "${DYAI_MASON_BIN}"
  for bin in pyls-bin ruff-bin fakels-bin; do
    printf '#!/usr/bin/env bash\n' > "${DYAI_MASON_BIN}/${bin}"
    chmod +x "${DYAI_MASON_BIN}/${bin}"
  done
  # Ruling 2: the exporter reads the exclude list from CONFIG_FILE's
  # global.lsp.exclude; genericls is excluded there, not in the fixture.
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${HOME}/.config/dyai/config.yaml" << 'CFG'
global:
  lsp:
    exclude: [genericls]
CFG
  export CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
}

function _skip_unless_nvim_available {
  command -v nvim &> /dev/null || skip "nvim not found"
}

function _stub {
  # shellcheck disable=SC2016 # the single quotes are deliberate: $0/$* expand in the stub, not here
  printf '#!/usr/bin/env bash\necho "STUB $(basename "$0") $*" >> "%s"\nexit 0\n' \
    "${HOME}/calls.log" > "${HOME}/.local/bin/${1}"
  chmod +x "${HOME}/.local/bin/${1}"
}

@test "dyai_lsp::export writes servers in languages.lua order with resolved commands" {
  _skip_unless_nvim_available
  # python = {pyls, ruffls}; fake = {fakels}; generic = {genericls}
  # genericls is in the exclude list; fnls has a function cmd
  dyai_lsp::export
  m="${XDG_CACHE_HOME}/dyai/lsp.json"
  # shellcheck disable=SC2312 # a bad export left the manifest absent; jq fails and so does the comparison
  [[ "$(jq -r '[.servers[].name] | join(",")' "${m}")" == "pyls,ruffls,fakels" ]]
  # shellcheck disable=SC2312 # a bad export left the manifest absent; jq fails and so does the comparison
  [[ "$(jq -r '.servers[0].command' "${m}")" == "${DYAI_MASON_BIN}/pyls-bin" ]]
  # shellcheck disable=SC2312 # a bad export left the manifest absent; jq fails and so does the comparison
  [[ "$(jq -r '.servers[0].extensions[".py"]' "${m}")" == "python" ]]
}

@test "dyai_lsp::export applies lsp/*.lua and plugins/lang cmd and settings overrides" {
  _skip_unless_nvim_available
  # fixture lsp/fakels.lua sets cmd {'fakels-bin','--stdio'};
  # lang/fake.lua sets opts.servers.fakels.settings = { fake = { on = true } }
  dyai_lsp::export
  m="${XDG_CACHE_HOME}/dyai/lsp.json"
  # shellcheck disable=SC2312 # a bad export left the manifest absent; jq fails and so does the comparison
  [[ "$(jq -c '.servers[] | select(.name=="fakels") | .args' "${m}")" == '["--stdio"]' ]]
  # shellcheck disable=SC2312 # a bad export left the manifest absent; jq fails and so does the comparison
  [[ "$(jq -c '.servers[] | select(.name=="fakels") | .settings' "${m}")" == '{"fake":{"on":true}}' ]]
}

@test "dyai_lsp::export converts review.lua hold patterns to ERE" {
  _skip_unless_nvim_available
  dyai_lsp::export
  # shellcheck disable=SC2312 # a bad export left the manifest absent; jq fails and so does the comparison
  [[ "$(jq -r '.untrusted_regexes[0]' "${XDG_CACHE_HOME}/dyai/lsp.json")" == '^(.*/\.worktrees/dyreview-[^/]+)(/|$)' ]]
}

@test "dyai_lsp::export applies overrides from a lang/*.lua returning a list of specs" {
  _skip_unless_nvim_available
  # fixture lang/listspec.lua returns a *list* of plugin specs (the real
  # config's cpp.lua shape), with the nvim-lspconfig entry among them.
  dyai_lsp::export
  m="${XDG_CACHE_HOME}/dyai/lsp.json"
  # shellcheck disable=SC2312 # a bad export left the manifest absent; jq fails and so does the comparison
  [[ "$(jq -c '.servers[] | select(.name=="pyls") | .settings' "${m}")" == '{"listspec":true}' ]]
}

@test "dyai_lsp::export logs and keeps going when config.globals or a lang file fails to load" {
  _skip_unless_nvim_available
  # fixture lua/config/globals.lua and lua/plugins/lang/broken.lua both
  # `error()` on load; the export must still succeed, with both logged.
  run dyai_lsp::export
  assert_success
  assert_output --partial "config.globals"
  assert_output --partial "broken.lua"
  m="${XDG_CACHE_HOME}/dyai/lsp.json"
  # shellcheck disable=SC2312 # a bad export left the manifest absent; jq fails and so does the comparison
  [[ "$(jq -r '.servers | length' "${m}")" -gt 0 ]]
}

@test "dyai_lsp::export keeps the old manifest when nvim is missing" {
  dybatpho::ensure_dir "${XDG_CACHE_HOME}/dyai" > /dev/null
  printf '{"version":1,"servers":[]}' > "${XDG_CACHE_HOME}/dyai/lsp.json"
  DYAI_NVIM="${BATS_TEST_TMPDIR}/no-such-nvim" run dyai_lsp::export
  assert_failure
  # shellcheck disable=SC2312 # a missing file would fail cat, and the comparison with it
  [[ "$(cat "${XDG_CACHE_HOME}/dyai/lsp.json")" == '{"version":1,"servers":[]}' ]]
}

# ---------------------------------------------------------------------------
# Ruling 1: generic owned-state helpers (Task 4 reuses these)
# ---------------------------------------------------------------------------

@test "dyai_lsp::owned_get reports null when the owned-state file is absent" {
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(dyai_lsp::owned_get claude_version)" == "null" ]]
}

@test "dyai_lsp::owned_set writes a key atomically, keeping other keys, owned_get reads it back" {
  dyai_lsp::owned_set claude_version '"1.2.3"'
  dyai_lsp::owned_set other_key '{"a":1}'
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(dyai_lsp::owned_get claude_version)" == '"1.2.3"' ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(dyai_lsp::owned_get other_key)" == '{"a":1}' ]]
  dyai_lsp::owned_set claude_version '"4.5.6"'
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(dyai_lsp::owned_get claude_version)" == '"4.5.6"' ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(dyai_lsp::owned_get other_key)" == '{"a":1}' ]]
}

# ---------------------------------------------------------------------------
# dyai_lsp::primary_extensions / dyai_lsp::launch_argv / dyai_lsp::setup_claude
# These write the manifest fixture directly as JSON; no nvim needed.
# ---------------------------------------------------------------------------

function _write_manifest {
  dybatpho::ensure_dir "${XDG_CACHE_HOME}/dyai" > /dev/null
  M="${XDG_CACHE_HOME}/dyai/lsp.json"
  cat > "${M}" << 'MANIFEST'
{
  "version": 1,
  "untrusted_regexes": [],
  "servers": [
    {
      "name": "pyls",
      "command": "/opt/pyls-bin",
      "args": ["--stdio"],
      "filetypes": ["python"],
      "extensions": {".py": "python", ".pyi": "python"},
      "settings": {},
      "init_options": {}
    },
    {
      "name": "ruffls",
      "command": "/opt/ruff-bin",
      "args": [],
      "filetypes": ["python"],
      "extensions": {".py": "python"},
      "settings": {},
      "init_options": {}
    },
    {
      "name": "fakels",
      "command": "/opt/fakels-bin",
      "args": ["--stdio"],
      "filetypes": ["fake"],
      "extensions": {".fk": "fake"},
      "settings": {"fake": {"on": true}},
      "init_options": {}
    }
  ]
}
MANIFEST
}

@test "dyai_lsp::primary_extensions gives each extension to the first server only" {
  _write_manifest
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(dyai_lsp::primary_extensions "${M}" | jq -c 'keys')" == '["fakels","pyls"]' ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(dyai_lsp::primary_extensions "${M}" | jq -c '.pyls')" == '{".py":"python",".pyi":"python"}' ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(dyai_lsp::primary_extensions "${M}" | jq -c '.fakels')" == '{".fk":"fake"}' ]]
}

@test "dyai_lsp::launch_argv wraps a server's command behind the launcher" {
  _write_manifest
  local server argv expected
  server="$(jq -c '.servers[] | select(.name=="pyls")' "${M}")"
  argv="$(dyai_lsp::launch_argv "${server}")"
  expected="[\"${HOME}/.local/bin/dyai-lsp-exec\",\"pyls\",\"--\",\"/opt/pyls-bin\",\"--stdio\"]"
  [[ "${argv}" == "${expected}" ]]
}

@test "dyai_lsp::setup_claude writes a launcher-wrapped .lsp.json and adds the marketplace once" {
  _write_manifest
  _stub claude
  dyai_lsp::setup_claude
  lsp="${XDG_DATA_HOME}/dyai/claude-marketplace/plugins/dyai-lsp/.lsp.json"
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(jq -r '.pyls.command' "${lsp}")" == "${HOME}/.local/bin/dyai-lsp-exec" ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(jq -c '.pyls.args[0:3]' "${lsp}")" == '["pyls","--","/opt/pyls-bin"]' ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(jq -r '.pyls | keys | join(",")' "${lsp}")" == "args,command,extensionToLanguage,maxRestarts" ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(jq -r '.fakels | keys | join(",")' "${lsp}")" == "args,command,extensionToLanguage,maxRestarts,settings" ]]
  marketplace="${XDG_DATA_HOME}/dyai/claude-marketplace/.claude-plugin/marketplace.json"
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(jq -r '.name' "${marketplace}")" == "dyai-lsp" ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(jq -r '.plugins[0].source' "${marketplace}")" == "./plugins/dyai-lsp" ]]
  plugin="${XDG_DATA_HOME}/dyai/claude-marketplace/plugins/dyai-lsp/.claude-plugin/plugin.json"
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(jq -r '.name' "${plugin}")" == "dyai-lsp" ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(jq -r '.version' "${plugin}")" =~ ^0\.0\.0-[0-9a-f]{12}$ ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  grep -q 'STUB claude plugin marketplace add' "${HOME}/calls.log"

  dybatpho::ensure_dir "${HOME}/.claude/plugins" > /dev/null
  printf '{"dyai-lsp":{}}' > "${HOME}/.claude/plugins/known_marketplaces.json"
  : > "${HOME}/calls.log"
  dyai_lsp::setup_claude
  [[ ! -s "${HOME}/calls.log" ]] # unchanged manifest: no add, no update
}

@test "dyai_lsp::setup_claude updates the plugin when the manifest changes" {
  _write_manifest
  _stub claude
  dybatpho::ensure_dir "${HOME}/.claude/plugins" > /dev/null
  printf '{"dyai-lsp":{}}' > "${HOME}/.claude/plugins/known_marketplaces.json"
  dyai_lsp::setup_claude
  : > "${HOME}/calls.log"
  # Change a server's args, which changes the generated .lsp.json and its hash.
  jq '.servers[0].args = ["--stdio", "--verbose"]' "${M}" > "${M}.tmp" && mv "${M}.tmp" "${M}"
  dyai_lsp::setup_claude
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  grep -q 'STUB claude plugin marketplace update dyai-lsp' "${HOME}/calls.log"
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  grep -q 'STUB claude plugin update dyai-lsp@dyai-lsp' "${HOME}/calls.log"
}

@test "dyai_lsp::setup_claude writes an empty plugin when there is no manifest" {
  _stub claude
  dyai_lsp::setup_claude
  lsp="${XDG_DATA_HOME}/dyai/claude-marketplace/plugins/dyai-lsp/.lsp.json"
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(cat "${lsp}")" == "{}" ]]
}

# ---------------------------------------------------------------------------
# Task 4: dyai_lsp::setup_copilot / setup_opencode / setup_hermes
# ---------------------------------------------------------------------------

function _lsp_agent_file {
  case "$1" in
    copilot) printf '%s\n' "${HOME}/.copilot/lsp-config.json" ;;
    opencode) printf '%s\n' "${HOME}/.config/opencode/opencode.json" ;;
    hermes) printf '%s\n' "${HOME}/.hermes/config.yaml" ;;
    *)
      printf 'unknown agent %s\n' "$1" >&2
      return 1
      ;;
  esac
}

function _lsp_seed_foreign {
  local agent file
  agent="$1"
  file="$(_lsp_agent_file "${agent}")"
  dybatpho::ensure_dir "$(dirname "${file}")" > /dev/null
  case "${agent}" in
    copilot) printf '{"lspServers":{"mine":{"command":"foreign"}}}' > "${file}" ;;
    opencode) printf '{"lsp":{"mine":{"command":["foreign"]}}}' > "${file}" ;;
    hermes) printf 'lsp:\n  servers:\n    mine:\n      command: ["foreign"]\n' > "${file}" ;;
    *)
      printf 'unknown agent %s\n' "${agent}" >&2
      return 1
      ;;
  esac
}

function _lsp_entries_json {
  local agent file
  agent="$1"
  file="$(_lsp_agent_file "${agent}")"
  case "${agent}" in
    copilot) jq -c '.lspServers // {}' "${file}" ;;
    opencode) jq -c '.lsp // {}' "${file}" ;;
    hermes) yq -o=json '.lsp.servers // {}' "${file}" ;;
    *)
      printf 'unknown agent %s\n' "${agent}" >&2
      return 1
      ;;
  esac
}

function _lsp_has_entry {
  local agent server
  agent="$1"
  server="$2"
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(_lsp_entries_json "${agent}" | jq -r --arg s "${server}" 'has($s)')" == "true" ]]
}

function _lsp_command0 {
  local agent server entries filter
  agent="$1"
  server="$2"
  entries="$(_lsp_entries_json "${agent}")"
  # shellcheck disable=SC2016 # $s is a jq variable, not a shell one
  case "${agent}" in
    copilot) filter='.[$s].command' ;;
    *) filter='.[$s].command[0]' ;;
  esac
  jq -r --arg s "${server}" "${filter}" <<< "${entries}"
}

function _lsp_seed_named {
  local agent name file
  agent="$1"
  name="$2"
  file="$(_lsp_agent_file "${agent}")"
  dybatpho::ensure_dir "$(dirname "${file}")" > /dev/null
  case "${agent}" in
    copilot) jq -n --arg n "${name}" '{lspServers: {($n): {command: "foreign"}}}' > "${file}" ;;
    opencode) jq -n --arg n "${name}" '{lsp: {($n): {command: ["foreign"]}}}' > "${file}" ;;
    hermes) printf 'lsp:\n  servers:\n    %s:\n      command: ["foreign"]\n' "${name}" > "${file}" ;;
    *)
      printf 'unknown agent %s\n' "${agent}" >&2
      return 1
      ;;
  esac
}

function _lsp_setup {
  dyai_lsp::"setup_$1"
}

@test "dyai_lsp::setup_<agent> writes launcher-wrapped entries and keeps foreign ones" {
  for agent in copilot opencode hermes; do
    _write_manifest
    _stub "${agent}"
    _lsp_seed_foreign "${agent}"
    _lsp_setup "${agent}"
    # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
    [[ "$(_lsp_command0 "${agent}" pyls)" == "${HOME}/.local/bin/dyai-lsp-exec" ]]
    _lsp_has_entry "${agent}" mine
  done
}

@test "dyai_lsp::setup_<agent> prunes a server removed from the manifest, never a foreign one" {
  for agent in copilot opencode hermes; do
    _write_manifest
    _stub "${agent}"
    _lsp_seed_foreign "${agent}"
    _lsp_setup "${agent}"
    _lsp_has_entry "${agent}" fakels
    jq 'del(.servers[] | select(.name == "fakels"))' "${M}" > "${M}.tmp" && mv "${M}.tmp" "${M}"
    _lsp_setup "${agent}"
    ! _lsp_has_entry "${agent}" fakels
    _lsp_has_entry "${agent}" pyls
    _lsp_has_entry "${agent}" mine
  done
}

@test "dyai_lsp::setup_<agent> is a no-op on the second run (mtime unchanged)" {
  for agent in copilot opencode hermes; do
    _write_manifest
    _stub "${agent}"
    _lsp_seed_foreign "${agent}"
    _lsp_setup "${agent}"
    local file before after
    file="$(_lsp_agent_file "${agent}")"
    before="$(stat -c %Y "${file}")"
    sleep 1
    _lsp_setup "${agent}"
    after="$(stat -c %Y "${file}")"
    [[ "${before}" == "${after}" ]]
  done
}

@test "dyai_lsp::setup_<agent> leaves a foreign entry colliding with a manifest server untouched" {
  for agent in copilot opencode hermes; do
    _write_manifest
    _stub "${agent}"
    _lsp_seed_named "${agent}" pyls
    _lsp_setup "${agent}"
    # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
    [[ "$(_lsp_command0 "${agent}" pyls)" == "foreign" ]]
    # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
    [[ "$(dyai_lsp::owned_get "${agent}" | jq 'index("pyls")')" == "null" ]]
    local file before after
    file="$(_lsp_agent_file "${agent}")"
    before="$(stat -c %Y "${file}")"
    sleep 1
    _lsp_setup "${agent}"
    after="$(stat -c %Y "${file}")"
    [[ "${before}" == "${after}" ]]
    # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
    [[ "$(_lsp_command0 "${agent}" pyls)" == "foreign" ]]
  done
}

@test "dyai_lsp::setup_hermes uses the Hermes built-in id for pyright" {
  dybatpho::ensure_dir "${XDG_CACHE_HOME}/dyai" > /dev/null
  M="${XDG_CACHE_HOME}/dyai/lsp.json"
  cat > "${M}" << 'MANIFEST'
{
  "version": 1,
  "untrusted_regexes": [],
  "servers": [
    {
      "name": "pyright",
      "command": "/opt/pyright-bin",
      "args": ["--stdio"],
      "filetypes": ["python"],
      "extensions": {".py": "python"},
      "settings": {},
      "init_options": {}
    }
  ]
}
MANIFEST
  _stub hermes
  dyai_lsp::setup_hermes
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(yq '.lsp.servers.pyright.command[0]' "${HOME}/.hermes/config.yaml")" == "${HOME}/.local/bin/dyai-lsp-exec" ]]
}

@test "dyai_lsp writers leave agent files untouched when the manifest is missing" {
  for agent in copilot opencode hermes; do
    _stub "${agent}"
    _lsp_seed_foreign "${agent}"
    local file before after
    file="$(_lsp_agent_file "${agent}")"
    before="$(cat "${file}")"
    run _lsp_setup "${agent}"
    assert_output --partial "manifest"
    after="$(cat "${file}")"
    [[ "${before}" == "${after}" ]]
  done
}

# ---------------------------------------------------------------------------
# Task 5: dyai_lsp::setup_serena (Codex, Gemini, agy bridge)
# ---------------------------------------------------------------------------

function _write_serena_manifest {
  dybatpho::ensure_dir "${XDG_CACHE_HOME}/dyai" > /dev/null
  M="${XDG_CACHE_HOME}/dyai/lsp.json"
  cat > "${M}" << 'MANIFEST'
{
  "version": 1,
  "untrusted_regexes": [],
  "servers": [
    {
      "name": "pyright",
      "command": "/opt/pyright-bin",
      "args": ["--stdio"],
      "filetypes": ["python"],
      "extensions": {".py": "python"},
      "settings": {},
      "init_options": {}
    },
    {
      "name": "gopls",
      "command": "/opt/mason/bin/gopls",
      "args": [],
      "filetypes": ["go"],
      "extensions": {".go": "go"},
      "settings": {},
      "init_options": {}
    }
  ]
}
MANIFEST
}

function _configure_serena {
  cat > "${CONFIG_FILE}" << 'CFG'
global:
  lsp:
    exclude: [genericls]
    serena:
      ref: abc123def
      contexts:
        codex: codex
        gemini: ide
        agy: antigravity
CFG
}

@test "dyai_lsp::setup_serena skips with a warning when uvx is missing" {
  _configure_serena
  # the real machine may have uvx installed elsewhere on PATH; restrict to
  # the sandbox bin dir only, where no stub was written for this test
  PATH="${HOME}/.local/bin" run dyai_lsp::setup_serena
  assert_failure
  assert_output --partial "uvx"
}

@test "dyai_lsp::setup_serena skips with a warning when global.lsp.serena.ref is unset" {
  _stub uvx
  run dyai_lsp::setup_serena
  assert_failure
  assert_output --partial "ref"
}

@test "dyai_lsp::setup_serena registers codex with --context codex and startup_timeout_sec inside mcp_servers.serena" {
  _write_serena_manifest
  _stub uvx
  _stub codex
  _configure_serena
  local chome file
  chome="${HOME}/.codex"
  dybatpho::ensure_dir "${chome}" > /dev/null
  file="${chome}/config.toml"
  cat > "${file}" << 'TOML'
model = "gpt-5"

[mcp_servers.other]
command = "other-cmd"
TOML
  dyai_lsp::setup_serena
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(yq -p=toml '.mcp_servers.serena.args[7]' "${file}")" == "--context" ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(yq -p=toml '.mcp_servers.serena.args[8]' "${file}")" == "codex" ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(yq -p=toml '.mcp_servers.serena.startup_timeout_sec' "${file}")" == "60" ]]
  # a pre-existing table and the other top-level key are untouched
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(yq -p=toml '.model' "${file}")" == "gpt-5" ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(yq -p=toml '.mcp_servers.other.command' "${file}")" == "other-cmd" ]]
}

@test "dyai_lsp::setup_serena uses --context ide for gemini and antigravity for agy" {
  _write_serena_manifest
  _stub uvx
  _stub gemini
  _stub agy
  _configure_serena
  dyai_lsp::setup_serena
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(jq -r '.mcpServers.serena.args[8]' "${HOME}/.gemini/settings.json")" == "ide" ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(jq -r '.mcpServers.serena.args[8]' "${HOME}/.gemini/config/mcp_config.json")" == "antigravity" ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(jq -r '.mcpServers.serena.env.SERENA_USAGE_REPORTING' "${HOME}/.gemini/settings.json")" == "false" ]]
}

@test "dyai_lsp::setup_serena never writes claude, copilot or opencode configuration" {
  _write_serena_manifest
  _stub uvx
  _stub gemini
  _configure_serena
  dyai_lsp::setup_serena
  [[ ! -e "${HOME}/.claude.json" ]]
  [[ ! -e "${HOME}/.copilot/lsp-config.json" ]]
  [[ ! -e "${HOME}/.copilot/mcp-config.json" ]]
  [[ ! -e "${HOME}/.config/opencode/opencode.json" ]]
}

@test "dyai_lsp::setup_serena writes a gopls PATH shim and sets PATH on the serena entry" {
  _write_serena_manifest
  _stub uvx
  _stub gemini
  _configure_serena
  dyai_lsp::setup_serena
  local shim
  shim="${XDG_DATA_HOME}/dyai/serena-shims/gopls"
  [[ -x "${shim}" ]]
  grep -q "${HOME}/.local/bin/dyai-lsp-exec" "${shim}"
  grep -q '/opt/mason/bin/gopls' "${shim}"
  local path_env
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  path_env="$(jq -r '.mcpServers.serena.env.PATH' "${HOME}/.gemini/settings.json")"
  [[ "${path_env}" == "${XDG_DATA_HOME}/dyai/serena-shims:"* ]]
}

@test "dyai_lsp::setup_serena removes the gopls shim once it leaves the manifest" {
  _write_serena_manifest
  _stub uvx
  _stub gemini
  _configure_serena
  dyai_lsp::setup_serena
  local shim
  shim="${XDG_DATA_HOME}/dyai/serena-shims/gopls"
  [[ -e "${shim}" ]]
  jq 'del(.servers[] | select(.name == "gopls"))' "${M}" > "${M}.tmp" && mv "${M}.tmp" "${M}"
  dyai_lsp::setup_serena
  [[ ! -e "${shim}" ]]
}

@test "dyai_lsp::setup_serena_config keeps a foreign key, writes python's ls_base_cmd, prunes a removed language" {
  _write_serena_manifest
  _configure_serena
  # shellcheck disable=SC2030 # a bats @test body runs in a single process, not a subshell
  export SERENA_HOME="${HOME}/.serena"
  dybatpho::ensure_dir "${SERENA_HOME}" > /dev/null
  cat > "${SERENA_HOME}/serena_config.yml" << 'YML'
ls_specific_settings:
  rust:
    ls_path: /opt/foreign-rust
YML
  dyai_lsp::setup_serena_config
  local file
  file="${SERENA_HOME}/serena_config.yml"
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(yq '.ls_specific_settings.rust.ls_path' "${file}")" == "/opt/foreign-rust" ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(yq '.ls_specific_settings.python.ls_base_cmd[0]' "${file}")" == "${HOME}/.local/bin/dyai-lsp-exec" ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(yq '.ls_specific_settings.python.ls_base_cmd[3]' "${file}")" == "/opt/pyright-bin" ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(yq -o=json '.projects' "${file}")" == "[]" ]]

  jq 'del(.servers[] | select(.name == "pyright"))' "${M}" > "${M}.tmp" && mv "${M}.tmp" "${M}"
  dyai_lsp::setup_serena_config
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(yq '.ls_specific_settings | has("python")' "${file}")" == "false" ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(yq '.ls_specific_settings.rust.ls_path' "${file}")" == "/opt/foreign-rust" ]]
}

@test "dyai_lsp::setup_serena_config is a no-op on a second run (mtime unchanged)" {
  _write_serena_manifest
  # shellcheck disable=SC2031 # a bats @test body runs in a single process, not a subshell
  export SERENA_HOME="${HOME}/.serena"
  dyai_lsp::setup_serena_config
  local file before after
  file="${SERENA_HOME}/serena_config.yml"
  before="$(stat -c %Y "${file}")"
  sleep 1
  dyai_lsp::setup_serena_config
  after="$(stat -c %Y "${file}")"
  [[ "${before}" == "${after}" ]]
}
