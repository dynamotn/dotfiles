setup() {
  load test_helper
  SCHEMA_FILE="${DOTFILES_DIR}/schemas/dyai.schema.yaml"
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
  blockedGitlab: false
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
  # 6 marketplaces, including a github and the git one
  [[ "$(yq '.marketplaces | length' "${out}")" == "6" ]]
  [[ "$(yq '.marketplaces.trailofbits.source.source' "${out}")" == "github" ]]
  [[ "$(yq '.marketplaces["agent-sec-ops-kit-skills"].source.source' "${out}")" == "git" ]]
  # 52 plugins, including known entries
  [[ "$(yq '.plugins | length' "${out}")" == "52" ]]
  yq -e '.plugins[] | select(. == "superpowers@claude-plugins-official")' "${out}" > /dev/null
  yq -e '.plugins[] | select(. == "trailmark@trailofbits")' "${out}" > /dev/null
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
  [[ "$(yq '.global.skills | length' "${out}")" == "10" ]]
  yq -e '.global.skills[] | select(. == "vercel-labs/skills@find-skills")' "${out}" > /dev/null
  yq -e '.global.skills[] | select(. == "anthropics/skills@mcp-builder")' "${out}" > /dev/null
  # moved into presets, so no longer global
  run yq -e '.global.skills[] | select(. == "Eyadkelleh/awesome-skills-security@llm-testing")' "${out}"
  assert_failure
  run yq -e '.global.skills[] | select(. == "samber/cc-skills-golang@golang-code-style")' "${out}"
  assert_failure
  [[ "$(yq '.global.mcp.laya.command' "${out}")" == */.local/bin/laya-mcp-server ]]
  [[ "$(yq '.global.mcp.laya.env.HF_HUB_DISABLE_TELEMETRY' "${out}")" == "1" ]]
  [[ "$(yq '.agents.claude.plugins | length' "${out}")" == "52" ]]
  [[ "$(yq '.agents.claude.marketplaces | length' "${out}")" == "6" ]]
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
  # The baseline stays the 10 cross-cutting skills.
  [[ "$(jq -n --argjson g "${gjson}" '$g | length')" == "10" ]]
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
    find "${cache}" -type f -name "${name}.md" | grep -q . \
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
  # SQL database servers; connection inherited from runtime env, no secret here.
  [[ "$(yq '.global.mcp.postgres.command' "${out}")" == "uvx" ]]
  [[ "$(yq '.global.mcp.mysql.command' "${out}")" == "bunx" ]]
  [[ "$(yq '.global.mcp.postgres.env | length' "${out}")" == "0" ]]
  # github carries only the env var NAME, never a value.
  yq '.global.mcp.github.args[]' "${out}" | grep -qx 'GITHUB_PERSONAL_ACCESS_TOKEN'
  # filesystem default scope is personal + community.
  yq '.global.mcp.filesystem.args[]' "${out}" | grep -q 'Working/personal'
  yq '.global.mcp.filesystem.args[]' "${out}" | grep -q 'Working/community'
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
  yq '.global.subagents[0].include[]' "${out}" | grep -q '01-core-development'
  yq '.global.subagents[0].include[]' "${out}" | grep -q '04-quality-security'
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
  yq '.registry.languages.go.skills[]' "${out}" | grep -q 'golang-code-style'
  # Phase 4: the full tool-boundary taxonomy
  [[ "$(yq '.registry.languages.frontend.subagents[0]' "${out}")" == "react-specialist" ]]
  [[ "$(yq '.registry.languages.go.skills | length' "${out}")" == "5" ]]
  [[ "$(yq '.registry.infra.docker.subagents[0]' "${out}")" == "docker-expert" ]]
  yq '.registry.infra.aws.skills[]' "${out}" | grep -q 'aws-iam'
  [[ "$(yq '.registry.infra.cicd.skills | length' "${out}")" == "3" ]]
  [[ "$(yq '.registry.infra.database.skills | length' "${out}")" == "2" ]]
  [[ "$(yq '.registry.presets.testing.skills | length' "${out}")" == "2" ]]
  [[ "$(yq '.registry.presets.security.skills | length' "${out}")" == "9" ]]
  # Registry-expansion presets (nvim-supported languages/tools)
  [[ "$(yq '.registry.languages.vue.subagents[0]' "${out}")" == "vue-expert" ]]
  [[ "$(yq '.registry.languages.swift.subagents[0]' "${out}")" == "swift-expert" ]]
  [[ "$(yq '.registry.languages.java.subagents | length' "${out}")" == "2" ]]
  [[ "$(yq '.registry.infra.ansible.subagents[0]' "${out}")" == "devops-engineer" ]]
  [[ "$(yq '.registry.infra.terragrunt.subagents[0]' "${out}")" == "terragrunt-expert" ]]
  [[ "$(yq '.registry.presets.datascience.subagents[0]' "${out}")" == "data-scientist" ]]
  [[ "$(yq '.registry.presets.docs.subagents[0]' "${out}")" == "technical-writer" ]]
  [[ "$(yq '.registry.presets.shell.skills | length' "${out}")" == "3" ]]
}
