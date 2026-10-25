setup() {
  load test_helper
  DYTOY_DIR="${DOTFILES_DIR}/home/.chezmoitemplates/dytoy"
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

function _render_hermes {
  local cfg="${1}" out="${2}"
  (
    cd "${DOTFILES_DIR}" || exit 1
    env HOME="${DOTFILES_REAL_HOME}" \
      XDG_CONFIG_HOME="${DOTFILES_REAL_XDG_CONFIG_HOME:-${DOTFILES_REAL_HOME}/.config}" \
      chezmoi --config "${cfg}" execute-template \
      <<< '{{ template "dytoy/hermes.yaml.tmpl" . }}' > "${out}" 2> "${out}.err"
  )
}

@test "hermes dytoy template pins the installer and names the tool on a pc" {
  _require_chezmoi
  local cfg="${BATS_TEST_TMPDIR}/pc.yaml"
  local out="${BATS_TEST_TMPDIR}/hermes.pc.yaml"
  _write_profile_config "${cfg}" "linux-gentoo" "pc" "openrc" "W" "A" "H"
  _render_hermes "${cfg}" "${out}" || fail "render failed: $(cat "${out}.err")"
  grep -q '^name: hermes$' "${out}"
  grep -q '^method: shell$' "${out}"
  # Pinned to a version tag, never to a moving branch.
  grep -q 'hermes-agent/v' "${out}"
  ! grep -q 'hermes-agent/main' "${out}"
}

@test "hermes dytoy template is omitted on a container profile" {
  _require_chezmoi
  local cfg="${BATS_TEST_TMPDIR}/container.yaml"
  local out="${BATS_TEST_TMPDIR}/hermes.container.yaml"
  _write_profile_config "${cfg}" "linux-alpine" "container" "openrc" "0" "" ""
  _render_hermes "${cfg}" "${out}" || fail "render failed: $(cat "${out}.err")"
  # Heavy toolchain: not installed on containers; the template renders blank.
  ! grep -q 'name: hermes' "${out}"
}
