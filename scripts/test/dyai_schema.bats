setup() {
  load test_helper
  SCHEMA_FILE="${DOTFILES_DIR}/scripts/lib/dyai/schemas/dyai.schema.yaml"
  CONFIG_TMPL="${DOTFILES_DIR}/home/private_dot_config/dyai/config.yaml.tmpl"
  DATA_PARTIAL="${DOTFILES_DIR}/home/.chezmoitemplates/ai/dyai-data.yaml.tmpl"
}

function _require_yq {
  command -v yq &> /dev/null || skip "yq not found"
}

# Render a .chezmoitemplates partial by name through chezmoi.
function _render_named {
  local name="${1}" out="${2}"
  (
    cd "${DOTFILES_DIR}" || exit 1
    env HOME="${DOTFILES_REAL_HOME}" \
      XDG_CONFIG_HOME="${DOTFILES_REAL_XDG_CONFIG_HOME:-${DOTFILES_REAL_HOME}/.config}" \
      chezmoi execute-template --source "${DOTFILES_DIR}" \
      <<< "{{ includeTemplate \"${name}\" . }}" > "${out}" 2> "${out}.err"
  )
}

# ---------------------------------------------------------------------------
# Helpers (mirrors dytoy_schema.bats)
# ---------------------------------------------------------------------------

function _require_ys {
  if ! command -v ys &> /dev/null; then
    skip "ys not found – install with: cargo install yaml-schema"
  fi
  YS="$(mise which ys 2> /dev/null || command -v ys)"
}

function _require_chezmoi {
  command -v chezmoi &> /dev/null || skip "chezmoi not found"
}

function _write_profile_config {
  local cfg="${1}"
  cat > "${cfg}" << EOF
sourceDir: "${DOTFILES_DIR}"
data:
  osid: "${2}"
  kind: "${3}"
  initSystem: "${4}"
  guiServer: "${5}"
  guiDriver: "${6}"
  guiWinManager: "${7}"
  browser: "F"
  mailClient: "T"
  languages: ["vi"]
  place: "home"
  code: "test-machine"
  company: ""
  hasSound: true
  hasBluetooth: true
  hasWifi: true
  bash: "/usr/bin/env bash"
  terminalMultiplexer: "Z"
  darkMode: true
  preferGitSSH: true
  decryptPersonal: false
  decryptEnterprise: []
  browserEnterpriseProfiles: []
  mailEnterpriseProfiles: []
EOF
}

# Render a managed .tmpl file (not a partial) and validate it against the schema.
function _render_config {
  local cfg="${1}" out="${2}"
  (
    cd "${DOTFILES_DIR}" || exit 1
    env HOME="${DOTFILES_REAL_HOME}" \
      XDG_CONFIG_HOME="${DOTFILES_REAL_XDG_CONFIG_HOME:-${DOTFILES_REAL_HOME}/.config}" \
      chezmoi --config "${cfg}" execute-template \
      < "${CONFIG_TMPL}" > "${out}" 2> "${out}.err"
  )
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "dyai schema yaml file exists" {
  [[ -f "${SCHEMA_FILE}" ]]
}

@test "rendered dyai config valid for profile: gentoo-pc" {
  _require_ys
  _require_chezmoi
  local cfg="${BATS_TEST_TMPDIR}/gentoo-pc.yaml"
  local out="${BATS_TEST_TMPDIR}/gentoo-pc.config.yaml"
  _write_profile_config "${cfg}" "linux-gentoo" "pc" "openrc" "W" "A" "H"
  if ! _render_config "${cfg}" "${out}"; then
    fail "chezmoi could not render config.yaml.tmpl: $(cat "${out}.err")"
  fi
  "${YS}" -f "${SCHEMA_FILE}" "${out}" > "${BATS_TEST_TMPDIR}/err" 2>&1 \
    || fail "schema validation failed: $(cat "${BATS_TEST_TMPDIR}/err")"
}

@test "rendered dyai config valid for profile: macos-laptop" {
  _require_ys
  _require_chezmoi
  local cfg="${BATS_TEST_TMPDIR}/macos-laptop.yaml"
  local out="${BATS_TEST_TMPDIR}/macos-laptop.config.yaml"
  _write_profile_config "${cfg}" "darwin" "laptop" "launchd" "M" "M" "A"
  if ! _render_config "${cfg}" "${out}"; then
    fail "chezmoi could not render config.yaml.tmpl: $(cat "${out}.err")"
  fi
  "${YS}" -f "${SCHEMA_FILE}" "${out}" > "${BATS_TEST_TMPDIR}/err" 2>&1 \
    || fail "schema validation failed: $(cat "${BATS_TEST_TMPDIR}/err")"
}

@test "shared data partial carries Claude marketplaces, plugins and policy" {
  _require_chezmoi
  _require_yq
  local out="${BATS_TEST_TMPDIR}/dyai-data.yaml"
  if ! _render_named "ai/dyai-data.yaml.tmpl" "${out}"; then
    fail "chezmoi could not render the data partial: $(cat "${out}.err")"
  fi
  # No counts here: adding a community plugin must not need a test edit.
  # Every plugin comes from a declared marketplace (or one Claude/dyai brings).
  local data
  data="$(yq -o=json -I=0 '.' "${out}")"
  jq -e '([.plugins[], .optional_plugins[]] | map(split("@")[1]) | unique)
    - ["claude-plugins-official", "dyai-lsp"] - (.marketplaces | keys)
    | length == 0' <<< "${data}" > /dev/null || fail "a plugin names an undeclared marketplace"
  [[ "$(yq '.marketplaces.trailofbits.source.source' "${out}")" == "github" ]]
  # Known entries, on globally and opt-in
  yq -e '.plugins[] | select(. == "superpowers@claude-plugins-official")' "${out}" > /dev/null
  yq -e '.optional_plugins[] | select(. == "trailmark@trailofbits")' "${out}" > /dev/null
  # agent-mode plugins, each its own single-plugin marketplace
  yq -e '.plugins[] | select(. == "ponytail@ponytail")' "${out}" > /dev/null
  # dyai-lsp replaces the official LSP plugins (registered at runtime, not here)
  yq -e '.plugins[] | select(. == "dyai-lsp@dyai-lsp")' "${out}" > /dev/null
  run yq -e '.plugins[] | select(. == "pyright-lsp@claude-plugins-official")' "${out}"
  assert_failure
  # ...and still-installed copies of them are switched off, never enabled
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(yq '.disabled_plugins | length' "${out}")" == "8" ]]
  yq -e '.disabled_plugins[] | select(. == "caveman@caveman")' "${out}" > /dev/null
  yq -e '.disabled_plugins[] | select(. == "rust-analyzer-lsp@claude-plugins-official")' "${out}" > /dev/null
  # shellcheck disable=SC2016,SC2312 # $p is a yq variable; a bad read fails the comparison
  [[ "$(yq '[.disabled_plugins[] as $p | .plugins[] | select(. == $p)] | length' "${out}")" == "0" ]]
  # policy
  [[ "$(yq '.policy.permissions.defaultMode' "${out}")" == "acceptEdits" ]]
  [[ "$(yq '.policy.theme' "${out}")" == "auto" ]]
  [[ "$(yq '.policy.effortLevel' "${out}")" == "medium" ]]
}

@test "rendered dyai config carries skills, laya mcp and claude plugins" {
  _require_chezmoi
  _require_yq
  local cfg="${BATS_TEST_TMPDIR}/gentoo-pc.yaml"
  local out="${BATS_TEST_TMPDIR}/gentoo-pc.full.yaml"
  _write_profile_config "${cfg}" "linux-gentoo" "pc" "openrc" "W" "A" "H"
  if ! _render_config "${cfg}" "${out}"; then
    fail "chezmoi could not render config.yaml.tmpl: $(cat "${out}.err")"
  fi
  # Phase 4: global.skills is trimmed to the cross-cutting baseline.
  yq -e '.global.skills[] | select(. == "vercel-labs/skills@find-skills")' "${out}" > /dev/null
  yq -e '.global.skills[] | select(. == "anthropics/skills@mcp-builder")' "${out}" > /dev/null
  # moved into presets, so no longer global
  run yq -e '.global.skills[] | select(. == "Eyadkelleh/awesome-skills-security@llm-testing")' "${out}"
  assert_failure
  run yq -e '.global.skills[] | select(. == "samber/cc-skills-golang@golang-code-style")' "${out}"
  assert_failure
  [[ "$(yq '.global.mcp.laya.command' "${out}")" == */.local/bin/laya-mcp ]]
  [[ "$(yq '.global.mcp.laya.env.HF_HUB_DISABLE_TELEMETRY' "${out}")" == "1" ]]
  # The Claude lists come through from the shared data partial.
  yq -e '.agents.claude.plugins[] | select(. == "superpowers@claude-plugins-official")' "${out}" > /dev/null
  yq -e '.agents.claude.optional_plugins[] | select(. == "secskills-core@secskills-marketplace")' "${out}" > /dev/null
  yq -e '.agents.claude.marketplaces | has("trailofbits")' "${out}" > /dev/null
  [[ "$(yq '.global.policy.theme' "${out}")" == "auto" ]]
}

@test "global stays lean and never overlaps a preset; presets never duplicate a skill" {
  _require_chezmoi
  _require_yq
  local cfg="${BATS_TEST_TMPDIR}/gentoo-pc.yaml"
  local out="${BATS_TEST_TMPDIR}/gentoo-pc.union.yaml"
  _write_profile_config "${cfg}" "linux-gentoo" "pc" "openrc" "W" "A" "H"
  _render_config "${cfg}" "${out}" || fail "render failed: $(cat "${out}.err")"
  local gjson pjson pcount puniq overlap unioncount
  gjson="$(yq -o=json -I=0 '.global.skills' "${out}")"
  pjson="$(yq -o=json -I=0 '[.registry.languages[].skills // [], .registry.infra[].skills // [], .registry.presets[].skills // []] | flatten' "${out}")"
  # The baseline stays a short cross-cutting list; a skill tied to a language,
  # tool or domain belongs in a preset. Only crossing this cap needs a test edit.
  [[ "$(jq -n --argjson g "${gjson}" '$g | length')" -le 15 ]]
  # Every skill is a skills.sh id or a GitHub tree URL pinned to a commit.
  jq -e -n --argjson g "${gjson}" --argjson p "${pjson}" '[$g[], $p[]]
    | all(test("^[^/@[:space:]]+/[^/@[:space:]]+@[^@[:space:]]+$")
      or test("^https://github\\.com/[^/]+/[^/]+/tree/[0-9a-f]{40}/"))' > /dev/null \
    || fail "a skill entry is neither owner/repo@skill nor a pinned tree URL"
  # A skill is either global or in a preset, never both.
  overlap="$(jq -n --argjson g "${gjson}" --argjson p "${pjson}" '[$g[] | select([.] | inside($p))] | length')"
  [[ "${overlap}" == "0" ]]
  # No skill appears in two presets.
  pcount="$(jq -n --argjson p "${pjson}" '$p | length')"
  puniq="$(jq -n --argjson p "${pjson}" '$p | unique | length')"
  [[ "${pcount}" == "${puniq}" ]]
  # Nothing from the Phase-4 redistribution was dropped (baseline of 42, now grown).
  unioncount="$(jq -n --argjson g "${gjson}" --argjson p "${pjson}" '($g + $p) | unique | length')"
  [[ "${unioncount}" -ge 42 ]]
}

@test "every registry subagent name exists in the pinned subagent repo" {
  _require_chezmoi
  _require_yq
  local cfg="${BATS_TEST_TMPDIR}/gentoo-pc.yaml"
  local out="${BATS_TEST_TMPDIR}/gentoo-pc.sacheck.yaml"
  _write_profile_config "${cfg}" "linux-gentoo" "pc" "openrc" "W" "A" "H"
  _render_config "${cfg}" "${out}" || fail "render failed: $(cat "${out}.err")"
  local repo ref cache
  repo="$(yq '.global.subagents[0].repo' "${out}")"
  ref="$(yq '.global.subagents[0].ref' "${out}")"
  # Match dyai::fetch_repo's cache layout (~/.cache/dyai/<repo|/=->-<ref>).
  cache="${DOTFILES_REAL_HOME}/.cache/dyai/${repo//\//-}-${ref}"
  [[ -d "${cache}" ]] || skip "pinned subagent repo not cached at ${cache}; run 'dyai use <preset>' once to populate"
  local name
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    # shellcheck disable=SC2312 # find yields the match or nothing; grep is the gate
    find "${cache}" -type f -name "${name}.md" | grep . > /dev/null \
      || fail "registry subagent '${name}' has no ${name}.md in ${repo}@${ref}"
  done < <(yq '[.registry.languages[].subagents // [], .registry.infra[].subagents // [], .registry.presets[].subagents // []] | flatten | .[]' "${out}")
}

@test "config declares shared notify hooks and the approval default" {
  _require_chezmoi
  _require_yq
  local cfg="${BATS_TEST_TMPDIR}/gentoo-pc.yaml"
  local out="${BATS_TEST_TMPDIR}/gentoo-pc.hooks.yaml"
  _write_profile_config "${cfg}" "linux-gentoo" "pc" "openrc" "W" "A" "H"
  _render_config "${cfg}" "${out}" || fail "render failed: $(cat "${out}.err")"
  [[ "$(yq '.global.hooks.stop.event' "${out}")" == "stop" ]]
  [[ "$(yq '.global.hooks.input.event' "${out}")" == "input" ]]
  yq -e '.global.hooks.stop.run | test("notify-send")' "${out}" > /dev/null
  [[ "$(yq '.global.policy.approval' "${out}")" == "accept-edits" ]]
}

@test "config carries the pinned community MCP servers" {
  _require_chezmoi
  _require_yq
  local cfg="${BATS_TEST_TMPDIR}/gentoo-pc.yaml"
  local out="${BATS_TEST_TMPDIR}/gentoo-pc.mcp.yaml"
  _write_profile_config "${cfg}" "linux-gentoo" "pc" "openrc" "W" "A" "H"
  _render_config "${cfg}" "${out}" || fail "render failed: $(cat "${out}.err")"
  [[ "$(yq '.global.mcp.fetch.command' "${out}")" == "uvx" ]]
  [[ "$(yq '.global.mcp."sequential-thinking".command' "${out}")" == "bunx" ]]
  [[ "$(yq '.global.mcp.github.command' "${out}")" == "docker" ]]
  # SQL database servers live in the database preset now, not the global baseline.
  [[ "$(yq '.global.mcp | has("postgres")' "${out}")" == "false" ]]
  [[ "$(yq '.global.mcp | has("mysql")' "${out}")" == "false" ]]
  # github carries only the env var NAME, never a value.
  yq '.global.mcp.github.args[]' "${out}" | grep -x 'GITHUB_PERSONAL_ACCESS_TOKEN' > /dev/null
  # filesystem default scope is personal + community.
  yq '.global.mcp.filesystem.args[]' "${out}" | grep 'Working/personal' > /dev/null
  yq '.global.mcp.filesystem.args[]' "${out}" | grep 'Working/community' > /dev/null
}

@test "dybrain MCP runs the vault's script only on kinds with Obsidian" {
  _require_chezmoi
  _require_yq
  local cfg="${BATS_TEST_TMPDIR}/laptop.yaml" out="${BATS_TEST_TMPDIR}/laptop.mcp.yaml"
  _write_profile_config "${cfg}" "darwin" "laptop" "launchd" "M" "M" "A"
  _render_config "${cfg}" "${out}" || fail "render failed: $(cat "${out}.err")"
  yq '.global.mcp.dybrain.command' "${out}" | grep '/.local/bin/dybrain-mcp$' > /dev/null
  yq '.global.mcp.dybrain.args[-1]' "${out}" \
    | grep '/Documents/DyBrain/99_System/99.03_Scripts/dev/vault-mcp.py$' > /dev/null
  cfg="${BATS_TEST_TMPDIR}/server.yaml" out="${BATS_TEST_TMPDIR}/server.mcp.yaml"
  _write_profile_config "${cfg}" "linux-gentoo" "server" "openrc" "N" "N" "N"
  _render_config "${cfg}" "${out}" || fail "render failed: $(cat "${out}.err")"
  [[ "$(yq '.global.mcp | has("dybrain")' "${out}")" == "false" ]]
}

@test "MCP pins clear the 7-day uv/bun release cooldown" {
  _require_chezmoi
  _require_yq
  command -v curl &> /dev/null || skip "curl not found"
  curl -fsS --max-time 10 -o /dev/null https://pypi.org/simple/ 2> /dev/null || skip "offline"
  local cfg="${BATS_TEST_TMPDIR}/gentoo-pc.yaml"
  local out="${BATS_TEST_TMPDIR}/gentoo-pc.mcp.yaml"
  _write_profile_config "${cfg}" "linux-gentoo" "pc" "openrc" "W" "A" "H"
  _render_config "${cfg}" "${out}" || fail "render failed: $(< "${out}.err")"
  # Every uvx/bunx server, global or in a preset, as `launcher<TAB>pkg<TAB>version`.
  local servers="${BATS_TEST_TMPDIR}/servers.json" pins="${BATS_TEST_TMPDIR}/pins"
  local meta="${BATS_TEST_TMPDIR}/meta.json"
  yq -o=json -I=0 '[.global.mcp[], .registry[][].mcp[]?] | .[]
    | select(.command == "uvx" or .command == "bunx")' "${out}" > "${servers}"
  jq -r '.command + "\t" + (.args[0] | capture("^(?<p>@?[^@]+)@(?<v>.+)$") | .p + "\t" + .v)' \
    "${servers}" > "${pins}"
  local launcher pkg ver published age now stamp bad=""
  printf -v now '%(%s)T' -1
  while IFS=$'\t' read -r launcher pkg ver; do
    published=""
    if [[ "${launcher}" == "uvx" ]]; then
      curl -fsS --max-time 20 -o "${meta}" "https://pypi.org/pypi/${pkg}/${ver}/json" \
        && published="$(jq -r '.urls[0].upload_time_iso_8601 // empty' "${meta}")"
    else
      curl -fsS --max-time 20 -o "${meta}" "https://registry.npmjs.org/${pkg/\//%2F}" \
        && published="$(jq -r --arg v "${ver}" '.time[$v] // empty' "${meta}")"
    fi
    if [[ -z "${published}" ]]; then
      bad+=" ${pkg}@${ver}(unpublished)"
      continue
    fi
    stamp="$(date -d "${published}" +%s)"
    age=$((now - stamp))
    ((age >= 7 * 86400)) || bad+=" ${pkg}@${ver}($((age / 86400))d)"
  done < "${pins}"
  [[ -z "${bad}" ]] || fail "pinned younger than the 7-day cooldown, so they never start:${bad}"
}

@test "every subagent excluded from the baseline is reachable from a preset" {
  _require_chezmoi
  _require_yq
  local cfg="${BATS_TEST_TMPDIR}/gentoo-pc.yaml"
  local out="${BATS_TEST_TMPDIR}/gentoo-pc.excl.yaml" j
  _write_profile_config "${cfg}" "linux-gentoo" "pc" "openrc" "W" "A" "H"
  _render_config "${cfg}" "${out}" || fail "render failed: $(< "${out}.err")"
  j="$(yq -o=json -I=0 '.' "${out}")"
  # Only these two are dropped on purpose: one installs agents behind dyai's
  # back, the other targets Windows/Azure operations.
  jq -e '["agent-installer", "it-ops-orchestrator"] as $dropped
    | [.registry[][] | .subagents // [] | .[]] as $preset
    | .global.subagents[0].exclude
    | all(. as $a | ($preset | index($a) != null) or ($dropped | index($a) != null))' \
    <<< "${j}" > /dev/null || fail "an excluded subagent is in no preset"
}

@test "every preset plugin is an optional plugin, off globally and installed" {
  _require_chezmoi
  _require_yq
  local cfg="${BATS_TEST_TMPDIR}/gentoo-pc.yaml"
  local out="${BATS_TEST_TMPDIR}/gentoo-pc.plugins.yaml" j
  _write_profile_config "${cfg}" "linux-gentoo" "pc" "openrc" "W" "A" "H"
  _render_config "${cfg}" "${out}" || fail "render failed: $(< "${out}.err")"
  j="$(yq -o=json -I=0 '.' "${out}")"
  # A preset may only switch on a plugin that is installed but off globally.
  jq -e '(.agents.claude.optional_plugins // []) as $opt
    | [.registry[][] | .plugins // [] | .[]] | all(. as $p | $opt | index($p) != null)' \
    <<< "${j}" > /dev/null || fail "a preset plugin is not in agents.claude.optional_plugins"
  # A plugin is either on globally or optional, never both.
  jq -e '(.agents.claude.plugins // []) - ((.agents.claude.plugins // []) - (.agents.claude.optional_plugins // []))
    | length == 0' <<< "${j}" > /dev/null || fail "a plugin is both global and optional"
  # Every optional plugin is reachable from at least one preset.
  jq -e '[.registry[][] | .plugins // [] | .[]] as $used
    | (.agents.claude.optional_plugins // []) | all(. as $p | $used | index($p) != null)' \
    <<< "${j}" > /dev/null || fail "an optional plugin no preset enables"
}

@test "schema accepts abstract subagent tiers and per-agent model choices" {
  _require_ys
  local good="${BATS_TEST_TMPDIR}/good.yaml"
  cat > "${good}" << 'YAML'
global:
  subagents:
    - {repo: a/b, ref: abc123, include: [x], models: {x: strong, y: inherit}}
agents:
  claude: {model_tiers: {strong: opus}}
  codex: {model_tiers: {strong: {model: qwen3-coder, provider: ollama, effort: high}}}
YAML
  "${YS}" -f "${SCHEMA_FILE}" "${good}" > "${BATS_TEST_TMPDIR}/err" 2>&1 \
    || fail "valid tiers rejected: $(< "${BATS_TEST_TMPDIR}/err")"
}

@test "schema accepts global.crew" {
  _require_ys
  local good="${BATS_TEST_TMPDIR}/good.yaml"
  cat > "${good}" << 'YAML'
global:
  crew:
    fallback: [claude, gemini]
    reviewer: {claude: gemini}
    model: {opencode: "anthropic/claude-sonnet-4-5"}
    timeout: 600
    require_review: false
    panes: "off"
    dybrain: false
    consensus: [{agent: copilot, stance: against}, {agent: codex}]
    ontology: docs/terms.yaml
    judge: {auto: false, laya: true, jev: false}
    fences: [":(glob)secrets/**"]
    hooks: {on_status: "true"}
YAML
  "${YS}" -f "${SCHEMA_FILE}" "${good}" > "${BATS_TEST_TMPDIR}/err" 2>&1 \
    || fail "valid crew config rejected: $(< "${BATS_TEST_TMPDIR}/err")"
}

@test "schema rejects an unknown crew agent" {
  _require_ys
  local bad="${BATS_TEST_TMPDIR}/bad.yaml"
  printf 'global:\n  crew:\n    fallback: [gpt]\n' > "${bad}"
  run "${YS}" -f "${SCHEMA_FILE}" "${bad}"
  assert_failure
  printf 'global:\n  crew:\n    model: {gpt: x}\n' > "${bad}"
  run "${YS}" -f "${SCHEMA_FILE}" "${bad}"
  assert_failure
}

@test "the domain catalog names only registry presets and only valid regexes" {
  _require_chezmoi
  _require_yq
  local cfg="${BATS_TEST_TMPDIR}/pc.yaml" out="${BATS_TEST_TMPDIR}/pc.config.yaml" registry bad re
  _write_profile_config "${cfg}" "linux-arch" "pc" "systemd" "W" "A" "H"
  _render_config "${cfg}" "${out}" || fail "chezmoi could not render config.yaml.tmpl: $(< "${out}.err")"
  registry="$(yq -o=json '.registry' "${out}")"
  # shellcheck disable=SC2016 # a jq program
  bad="$(jq -r '([.languages, .infra, .presets] | map(keys) | add) as $k
    | .domains | to_entries[] | .key as $d | .value.presets[] | select(IN($k[]) | not) | "\($d): \(.)"' \
    <<< "${registry}")"
  [[ -z "${bad}" ]] || fail "unknown presets: ${bad}"
  local count
  count="$(jq '.domains | length' <<< "${registry}")"
  ((count > 50)) || fail "the catalog lost its domains: ${count}"
  while IFS= read -r re; do
    grep -Eq -- "${re}" /dev/null && :
    (($? < 2)) || fail "bad regex: ${re}"
  done < <(jq -r '.domains[].detect[]? | (.match, .deps) // empty' <<< "${registry}" || true)
}

@test "the repository ontology matches its schema and names only its own domains" {
  _require_ys
  _require_yq
  local onto="${DOTFILES_DIR}/docs/ontology.yaml"
  "${YS}" -f "${DOTFILES_DIR}/scripts/lib/dyai/schemas/ontology.schema.yaml" "${onto}" > "${BATS_TEST_TMPDIR}/err" 2>&1 \
    || fail "ontology rejected: $(< "${BATS_TEST_TMPDIR}/err")"
  # shellcheck disable=SC2016 # a yq expression
  run yq -r '[.domains[].id] as $d | .terms[] | select(.domain and ([.domain] - $d | length > 0)) | .term' "${onto}"
  assert_output ""
}

@test "the ontology schema rejects a term without a meaning" {
  _require_ys
  local bad="${BATS_TEST_TMPDIR}/bad.yaml"
  printf 'domains: [{id: a, description: x}]\nterms: [{term: t}]\n' > "${bad}"
  run "${YS}" -f "${DOTFILES_DIR}/scripts/lib/dyai/schemas/ontology.schema.yaml" "${bad}"
  assert_failure
}

@test "schema rejects an unknown crew hook" {
  _require_ys
  local bad="${BATS_TEST_TMPDIR}/bad.yaml"
  printf 'global:\n  crew:\n    hooks: {pre_merge: x}\n' > "${bad}"
  run "${YS}" -f "${SCHEMA_FILE}" "${bad}"
  assert_failure
}

@test "schema rejects an unknown crew profile" {
  _require_ys
  local bad="${BATS_TEST_TMPDIR}/bad.yaml"
  printf 'global:\n  crew:\n    profile: tiny\n' > "${bad}"
  run "${YS}" -f "${SCHEMA_FILE}" "${bad}"
  assert_failure
}

@test "schema rejects an unknown crew panes mode" {
  _require_ys
  local bad="${BATS_TEST_TMPDIR}/bad.yaml"
  printf 'global:\n  crew:\n    panes: always\n' > "${bad}"
  run "${YS}" -f "${SCHEMA_FILE}" "${bad}"
  assert_failure
}

@test "schema rejects an agent model name used as a subagent tier" {
  _require_ys
  local bad="${BATS_TEST_TMPDIR}/bad.yaml"
  printf 'global:\n  subagents:\n    - {repo: a/b, ref: abc123, include: [x], models: {x: opus}}\n' > "${bad}"
  run "${YS}" -f "${SCHEMA_FILE}" "${bad}"
  assert_failure
}

@test "config declares the baseline subagents from VoltAgent at a pinned ref" {
  _require_chezmoi
  _require_yq
  local cfg="${BATS_TEST_TMPDIR}/gentoo-pc.yaml"
  local out="${BATS_TEST_TMPDIR}/gentoo-pc.sa.yaml"
  _write_profile_config "${cfg}" "linux-gentoo" "pc" "openrc" "W" "A" "H"
  _render_config "${cfg}" "${out}" || fail "render failed: $(cat "${out}.err")"
  [[ "$(yq '.global.subagents[0].repo' "${out}")" == "VoltAgent/awesome-claude-code-subagents" ]]
  [[ "$(yq '.global.subagents[0].ref' "${out}")" == "408d3c9eee2d" ]]
  yq '.global.subagents[0].include[]' "${out}" | grep '01-core-development' > /dev/null
  yq '.global.subagents[0].include[]' "${out}" | grep '04-quality-security' > /dev/null
}

@test "config declares the LSP sharing settings: exclude list and serena pin" {
  _require_chezmoi
  _require_yq
  local cfg="${BATS_TEST_TMPDIR}/gentoo-pc.yaml"
  local out="${BATS_TEST_TMPDIR}/gentoo-pc.lsp.yaml"
  _write_profile_config "${cfg}" "linux-gentoo" "pc" "openrc" "W" "A" "H"
  _render_config "${cfg}" "${out}" || fail "render failed: $(cat "${out}.err")"
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(yq '.global.lsp.serena.ref' "${out}")" == "abb0a0f01b94bc8050086f0fb860077d17730324" ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(yq '.global.lsp.exclude | length' "${out}")" == "6" ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(yq '.global.lsp.serena.contexts.codex' "${out}")" == "codex" ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(yq '.global.lsp.serena.contexts.gemini' "${out}")" == "ide" ]]
  # shellcheck disable=SC2312 # a bad read fails the comparison, which is the test
  [[ "$(yq '.global.lsp.serena.contexts.agy' "${out}")" == "antigravity" ]]
}

@test "schema rejects global.lsp.exclude as a scalar instead of an array" {
  _require_ys
  _require_chezmoi
  local out="${BATS_TEST_TMPDIR}/lsp-bad.yaml"
  cat > "${out}" << 'EOF'
global:
  lsp:
    exclude: "x"
agents: {}
EOF
  run "${YS}" -f "${SCHEMA_FILE}" "${out}"
  assert_failure
}

@test "config declares a registry of language and infra presets" {
  _require_chezmoi
  _require_yq
  local cfg="${BATS_TEST_TMPDIR}/gentoo-pc.yaml"
  local out="${BATS_TEST_TMPDIR}/gentoo-pc.reg.yaml"
  _write_profile_config "${cfg}" "linux-gentoo" "pc" "openrc" "W" "A" "H"
  _render_config "${cfg}" "${out}" || fail "render failed: $(cat "${out}.err")"
  [[ "$(yq '.registry.languages.go.subagents[0]' "${out}")" == "golang-pro" ]]
  [[ "$(yq '.registry.infra.terraform.subagents[0]' "${out}")" == "terraform-engineer" ]]
  yq '.registry.languages.go.skills[]' "${out}" | grep 'golang-code-style' > /dev/null
  # Phase 4: the full tool-boundary taxonomy
  # No per-preset skill counts: adding a community skill must not need a test
  # edit. Every preset carries something, and these name the ones that must.
  local registry
  registry="$(yq -o=json -I=0 '.registry' "${out}")"
  jq -e '[.languages, .infra, .presets | .[]] | all((.skills // []) + (.subagents // []) + (.plugins // [])
    + (.commands // []) + ((.mcp // {}) | keys) | length > 0)' <<< "${registry}" > /dev/null \
    || fail "a registry preset is empty"
  jq -e '. as $r | {registry: $r} | [.registry.languages.go, .registry.infra.cicd, .registry.infra.database,
    .registry.presets.testing, .registry.presets.security, .registry.presets.shell,
    .registry.presets.lifeos, .registry.infra.terraform, .registry.infra.cloudflare,
    .registry.infra.mongodb, .registry.presets.graphql, .registry.presets.mobile,
    .registry.presets.sentry, .registry.presets.opentelemetry, .registry.presets.context,
    .registry.presets.sre, .registry.presets.finops, .registry.presets.architecture,
    .registry.presets.product, .registry.infra.gcp, .registry.presets.datadog,
    .registry.infra.pulumi, .registry.presets.office]
    | all((.skills // []) | length > 0)' <<< "${registry}" > /dev/null || fail "a skills preset lost its skills"
  [[ "$(yq '.registry.languages.frontend.subagents[0]' "${out}")" == "react-specialist" ]]
  [[ "$(yq '.registry.infra.docker.subagents[0]' "${out}")" == "docker-expert" ]]
  yq '.registry.infra.aws.skills[]' "${out}" | grep 'aws-iam' > /dev/null
  # Registry-expansion presets (nvim-supported languages/tools)
  [[ "$(yq '.registry.languages.vue.subagents[0]' "${out}")" == "vue-expert" ]]
  [[ "$(yq '.registry.languages.swift.subagents[0]' "${out}")" == "swift-expert" ]]
  [[ "$(yq '.registry.languages.java.subagents | length' "${out}")" == "2" ]]
  [[ "$(yq '.registry.infra.ansible.subagents[0]' "${out}")" == "devops-engineer" ]]
  [[ "$(yq '.registry.infra.terragrunt.subagents[0]' "${out}")" == "terragrunt-expert" ]]
  [[ "$(yq '.registry.presets.datascience.subagents[0]' "${out}")" == "data-scientist" ]]
  [[ "$(yq '.registry.presets.docs.subagents[0]' "${out}")" == "technical-writer" ]]
  # SQL MCP moved into the database preset (per-project, not global)
  [[ "$(yq '.registry.infra.database.mcp.postgres.command' "${out}")" == "uvx" ]]
  [[ "$(yq '.registry.infra.database.mcp.mysql.command' "${out}")" == "bunx" ]]
  # Domain subagents split out of the global baseline into presets
  [[ "$(yq '.registry.presets.graphql.subagents[0]' "${out}")" == "graphql-architect" ]]
  [[ "$(yq '.registry.presets.mobile.subagents[0]' "${out}")" == "mobile-developer" ]]
  [[ "$(yq '.registry.presets.desktop.subagents[0]' "${out}")" == "electron-pro" ]]
  [[ "$(yq '.registry.presets.realtime.subagents | length' "${out}")" == "2" ]]
  # LifeOS skills, pinned to a commit by tree URL
  yq '.registry.presets.lifeos.skills[]' "${out}" \
    | grep -x 'https://github.com/danielmiessler/LifeOS/tree/[0-9a-f]\{40\}/LifeOS/install/skills/RedTeam' > /dev/null
  yq '.global.subagents[0].exclude[]' "${out}" | grep -x 'electron-pro' > /dev/null
  # shellcheck disable=SC2312 # a bad read yields no match, which grep's own exit code catches
  yq '.global.subagents[0].exclude[]' "${out}" | grep -x 'graphql-architect' > /dev/null
  # Context-engineering skills, pinned to a commit by tree URL
  yq '.registry.presets.context.skills[]' "${out}" \
    | grep -x 'https://github.com/muratcankoylan/Agent-Skills-for-Context-Engineering/tree/[0-9a-f]\{40\}/skills/tool-design' > /dev/null
  # Role presets: SRE, platform, FinOps, architecture, product, extra clouds
  yq -e '.registry.presets.sre.subagents[0] == "sre-engineer"
    and .registry.presets.grafana.mcp.grafana.command == "docker"
    and .registry.presets.platform.subagents[0] == "platform-engineer"
    and .registry.presets.product.subagents[0] == "business-analyst"
    and .registry.infra.kubernetes.mcp.kubernetes.command == "bunx"
    and .registry.infra.azure.subagents[0] == "azure-infra-engineer"
    and .registry.infra.gcp.mcp.gcloud.command == "bunx"
    and .registry.infra.gitops.mcp.argocd.args[1] == "stdio"' "${out}" > /dev/null
  # Community vendor presets: observability, data, trackers, LLM tooling
  yq -e '(.registry.presets.datadog.skills[0]
      | test("^https://github.com/datadog-labs/agent-skills/tree/[0-9a-f]{40}/dd-apm$"))
    and .registry.infra.dbt.subagents[0] == "data-engineer"
    and .registry.presets.jira.mcp.atlassian.command == "uvx"
    and .registry.presets.linear.mcp.linear.args[1] == "https://mcp.linear.app/mcp"
    and .registry.presets.stripe.subagents[0] == "payment-integration"
    and .registry.presets.llm.subagents[0] == "ai-engineer"
    and .registry.presets.compliance.subagents[0] == "hipaa-compliance"
    and .registry.presets.modernization.subagents[0] == "legacy-modernizer"' "${out}" > /dev/null
}
