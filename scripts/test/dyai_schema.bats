setup() {
  load test_helper
  SCHEMA_FILE="${DOTFILES_DIR}/schemas/dyai.schema.yaml"
  CONFIG_TMPL="${DOTFILES_DIR}/home/private_dot_config/dyai/config.yaml.tmpl"
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
