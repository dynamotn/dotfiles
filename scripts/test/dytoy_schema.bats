# dyshellint disable=SC2154 DOTFILES_DIR, DOTFILES_REAL_HOME and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  SCHEMA_FILE="${DOTFILES_DIR}/schemas/dytoy.schema.yaml"
  DOC_SCHEMA_FILE="${DOTFILES_DIR}/schemas/dytoy-doc.schema.yaml"
  DYTOY_DIR="${DOTFILES_DIR}/home/.chezmoitemplates/dytoy"
  EXTRA_FILE="${DOTFILES_DIR}/docs/dytoy.extra.yaml"
  . "${DOTFILES_DIR}/scripts/lib/dytoy_docs.sh"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function _require_ys {
  if ! command -v ys &> /dev/null; then
    skip "ys not found – install with: cargo install yaml-schema"
  fi
  # A version manager shim costs ~15 ms a call, paid ~200 times per profile.
  YS="$(mise which ys 2> /dev/null || command -v ys)"
}

# Validate a plain definition against the schema, without its doc blocks.
function _validate_plain {
  local stripped
  mkdir -p "${BATS_TEST_TMPDIR}/stripped"
  stripped="${BATS_TEST_TMPDIR}/stripped/$(basename "${1}")"
  dytoy_docs::strip "${1}" > "${stripped}"
  "${YS}" -f "${SCHEMA_FILE}" "${stripped}"
}

function _require_chezmoi {
  command -v chezmoi &> /dev/null || skip "chezmoi not found"
}

# Write a temporary chezmoi config for a given distro profile.
# Usage: _write_profile_config <output_file> <osid> <kind> <initSystem> \
#                              <guiServer> <guiDriver> <guiWinManager>
function _write_profile_config {
  local cfg osid kind initSystem guiServer guiDriver guiWinManager
  cfg="${1}"
  osid="${2}"
  kind="${3}"
  initSystem="${4}"
  guiServer="${5}"
  guiDriver="${6}"
  guiWinManager="${7}"

  cat > "${cfg}" << EOF
sourceDir: "${DOTFILES_DIR}"
data:
  osid: "${osid}"
  kind: "${kind}"
  initSystem: "${initSystem}"
  guiServer: "${guiServer}"
  guiDriver: "${guiDriver}"
  guiWinManager: "${guiWinManager}"
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

# Render a .yaml.tmpl file using the given chezmoi config and write output.
# chezmoi's errors go to `<output>.err`.
function _render_template {
  local cfg="${1}" tmpl="${2}" out="${3}"
  (
    cd "${DOTFILES_DIR}" || exit 1
    env HOME="${DOTFILES_REAL_HOME}" \
      XDG_CONFIG_HOME="${DOTFILES_REAL_XDG_CONFIG_HOME:-${DOTFILES_REAL_HOME}/.config}" \
      chezmoi --config "${cfg}" execute-template \
      < "${tmpl}" > "${out}" 2> "${out}.err"
  )
}

# Render all .yaml.tmpl files with the given chezmoi config and validate each.
# Collects all failures and reports them together.
#
# Every template goes through one chezmoi run, each behind a marker line, and
# the output is split back into one file per template: chezmoi spends ~140 ms
# starting up, which across ~200 templates and six profiles was most of the
# suite's time. A template that fails to render now fails the profile instead
# of being skipped as if it had rendered nothing.
function _validate_profile {
  local profile="${1}" cfg="${2}"
  local failures=()
  local batch="${BATS_TEST_TMPDIR}/${profile}.batch.tmpl"
  local rendered="${BATS_TEST_TMPDIR}/${profile}.rendered"
  local out_dir="${BATS_TEST_TMPDIR}/${profile}"
  mkdir -p "${out_dir}"

  local tmpl name
  : > "${batch}"
  for tmpl in "${DYTOY_DIR}"/*.yaml.tmpl; do
    name="$(basename "${tmpl}")"
    printf '\n#==8<== %s\n{{ template "dytoy/%s" . }}\n' "${name%.tmpl}" "${name}" >> "${batch}"
  done
  if ! _render_template "${cfg}" "${batch}" "${rendered}"; then
    fail "chezmoi could not render the dytoy templates for ${profile}: $(< "${rendered}.err")"
  fi
  awk -v dir="${out_dir}" '
    /^#==8<== / { file = dir "/" $2; printf "" > file; next }
    file { print >> file }
  ' "${rendered}"

  local out validated=0
  for out in "${out_dir}"/*.yaml; do
    # Skip when output is empty, whitespace-only, or contains only YAML comments
    # (template condition was false or tool not applicable on this profile).
    grep -qv -e '^[[:space:]]*#' -e '^[[:space:]]*$' "${out}" || continue

    # ys writes validation errors to stdout; capture that for the failure message.
    validated=$((validated + 1))
    if ! "${YS}" -f "${SCHEMA_FILE}" "${out}" > "${BATS_TEST_TMPDIR}/err" 2>&1; then
      failures+=("$(basename "${out}").tmpl: $(cat "${BATS_TEST_TMPDIR}/err")")
    fi
  done
  # A marker the split no longer matches would leave nothing to validate.
  ((validated > 0)) || failures+=("no template rendered any tool for ${profile}")

  if ((${#failures[@]} > 0)); then
    fail "$(printf '%s\n' "${failures[@]}")"
  fi
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "dytoy schema yaml file exists" {
  [[ -f "${SCHEMA_FILE}" ]]
}

@test "plain dytoy yaml files conform to schema" {
  _require_ys
  local failures=()
  for yaml in "${DYTOY_DIR}"/*.yaml; do
    if ! _validate_plain "${yaml}" > "${BATS_TEST_TMPDIR}/err" 2>&1; then
      failures+=("$(basename "${yaml}"): $(cat "${BATS_TEST_TMPDIR}/err")")
    fi
  done
  ((${#failures[@]} == 0)) || fail "$(printf '%s\n' "${failures[@]}")"
}

@test "a doc block does not break the plain yaml check" {
  _require_ys
  printf '{{- /* doc\nname: ssh\n*/ -}}\nname: ssh\nmethod: os\n' > "${BATS_TEST_TMPDIR}/ssh.yaml"
  run _validate_plain "${BATS_TEST_TMPDIR}/ssh.yaml"
  assert_success
}

@test "doc schema rejects a block without a description" {
  _require_ys
  printf 'name: ssh\ncategory: A\nsubcategory: x\n' > "${BATS_TEST_TMPDIR}/block.yaml"
  run "${YS}" -f "${DOC_SCHEMA_FILE}" "${BATS_TEST_TMPDIR}/block.yaml"
  assert_failure
  printf 'name: ssh\ndescription: SSH client\ncategory: A\nsubcategory: x\nurl: none\norder: 10\n' \
    > "${BATS_TEST_TMPDIR}/block.yaml"
  run "${YS}" -f "${DOC_SCHEMA_FILE}" "${BATS_TEST_TMPDIR}/block.yaml"
  assert_success
}

@test "doc blocks conform to doc schema" {
  _require_ys
  local failures=() file count index block="${BATS_TEST_TMPDIR}/block.yaml" body
  for file in "${DYTOY_DIR}"/*.yaml "${DYTOY_DIR}"/*.yaml.tmpl "${EXTRA_FILE}"; do
    [[ -f "${file}" ]] || continue
    if [[ "${file}" == "${EXTRA_FILE}" ]]; then
      body="$(yq '.[] | split_doc' "${file}")"
    else
      body="$(dytoy_docs::blocks "${file}")"
      body="$(yq 'del(.file)' <<< "${body}")"
    fi
    [[ -n "${body}" ]] || continue
    count="$(yq ea '[.] | length' <<< "${body}")"
    for ((index = 0; index < count; index++)); do
      INDEX="${index}" yq 'select(document_index == env(INDEX))' <<< "${body}" > "${block}"
      "${YS}" -f "${DOC_SCHEMA_FILE}" "${block}" > "${BATS_TEST_TMPDIR}/err" 2>&1 \
        || failures+=("$(basename "${file}") block ${index}: $(cat "${BATS_TEST_TMPDIR}/err")")
    done
  done
  ((${#failures[@]} == 0)) || fail "$(printf '%s\n' "${failures[@]}")"
}

@test "rendered templates valid for profile: arch-laptop" {
  _require_ys
  _require_chezmoi
  local cfg="${BATS_TEST_TMPDIR}/arch-laptop.yaml"
  _write_profile_config "${cfg}" "linux-arch" "laptop" "systemd" "W" "I" "H"
  _validate_profile "arch-laptop" "${cfg}"
}

@test "rendered templates valid for profile: arch-laptop-niri" {
  _require_ys
  _require_chezmoi
  local cfg="${BATS_TEST_TMPDIR}/arch-laptop-niri.yaml"
  _write_profile_config "${cfg}" "linux-arch" "laptop" "systemd" "W" "I" "N"
  _validate_profile "arch-laptop-niri" "${cfg}"
}

@test "rendered templates valid for profile: gentoo-pc-niri" {
  _require_ys
  _require_chezmoi
  local cfg="${BATS_TEST_TMPDIR}/gentoo-pc-niri.yaml"
  _write_profile_config "${cfg}" "linux-gentoo" "pc" "openrc" "W" "A" "N"
  _validate_profile "gentoo-pc-niri" "${cfg}"
}

@test "rendered templates valid for profile: ubuntu-pc" {
  _require_ys
  _require_chezmoi
  local cfg="${BATS_TEST_TMPDIR}/ubuntu-pc.yaml"
  _write_profile_config "${cfg}" "linux-ubuntu" "pc" "systemd" "W" "I" "H"
  _validate_profile "ubuntu-pc" "${cfg}"
}

@test "rendered templates valid for profile: alpine-container" {
  _require_ys
  _require_chezmoi
  local cfg="${BATS_TEST_TMPDIR}/alpine-container.yaml"
  _write_profile_config "${cfg}" "linux-alpine" "container" "openrc" "0" "" ""
  _validate_profile "alpine-container" "${cfg}"
}

@test "rendered templates valid for profile: gentoo-pc" {
  _require_ys
  _require_chezmoi
  local cfg="${BATS_TEST_TMPDIR}/gentoo-pc.yaml"
  _write_profile_config "${cfg}" "linux-gentoo" "pc" "openrc" "W" "A" "H"
  _validate_profile "gentoo-pc" "${cfg}"
}

@test "rendered templates valid for profile: macos-laptop" {
  _require_ys
  _require_chezmoi
  local cfg="${BATS_TEST_TMPDIR}/macos-laptop.yaml"
  _write_profile_config "${cfg}" "darwin" "laptop" "launchd" "M" "M" "A"
  _validate_profile "macos-laptop" "${cfg}"
}

@test "rendered templates valid for profile: macos-laptop-omniwm" {
  _require_ys
  _require_chezmoi
  local cfg="${BATS_TEST_TMPDIR}/macos-laptop-omniwm.yaml"
  _write_profile_config "${cfg}" "darwin" "laptop" "launchd" "M" "M" "O"
  _validate_profile "macos-laptop-omniwm" "${cfg}"
}

@test "rendered templates valid for profile: android-mobile" {
  _require_ys
  _require_chezmoi
  local cfg="${BATS_TEST_TMPDIR}/android-mobile.yaml"
  _write_profile_config "${cfg}" "android" "mobile" "termux" "0" "" ""
  _validate_profile "android-mobile" "${cfg}"
}
