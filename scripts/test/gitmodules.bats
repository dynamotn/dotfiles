setup() {
  load test_helper
  TEMPLATE="${DOTFILES_DIR}/cascadeur/dot_gitmodules.tmpl"
  GITMODULES="${DOTFILES_DIR}/.gitmodules"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function _require_chezmoi {
  command -v chezmoi &> /dev/null || skip "chezmoi not found"
}

# Write a chezmoi config exercising one combination of the knobs the
# .gitmodules template branches on.
# Usage: _write_config <file> <multiplexer> <guiServer> <browser> [mailClient]
function _write_config {
  local cfg="${1}" multiplexer="${2}" guiServer="${3}" browser="${4}" mailClient="${5-T}"

  cat > "${cfg}" << EOF
sourceDir: "${DOTFILES_DIR}/cascadeur"
data:
  terminalMultiplexer: "${multiplexer}"
  guiServer: "${guiServer}"
  browser: "${browser}"
  mailClient: "${mailClient}"
  preferGitSSH: true
  code: "ci"
  company:
  decryptPersonal: true
  decryptEnterprise: ["F1"]
  browserEnterpriseProfiles: ["F1"]
  mailEnterpriseProfiles: ["F1"]
EOF
}

# Render the template with one config and append "name<TAB>path" lines.
function _collect_entries {
  local cfg="${1}" out="${2}"
  local rendered="${BATS_TEST_TMPDIR}/rendered"
  (
    cd "${DOTFILES_DIR}" || exit 1
    env HOME="${DOTFILES_REAL_HOME}" \
      XDG_CONFIG_HOME="${DOTFILES_REAL_XDG_CONFIG_HOME:-${DOTFILES_REAL_HOME}/.config}" \
      chezmoi --config "${cfg}" execute-template \
      < "${TEMPLATE}" > "${rendered}" 2> /dev/null
  )
  awk '
    /^\[submodule "/ { name = $0; sub(/^\[submodule "/, "", name); sub(/"\]$/, "", name) }
    /^[[:space:]]*path = / { path = $3; if (name != "") print name "\t" path }
  ' "${rendered}" >> "${out}"
}

# Every combination the template branches on. Paths never depend on the
# gitlab/ssh knobs, so those stay fixed here; only the urls they pick differ.
function _render_all_profiles {
  local out="${1}"
  : > "${out}"
  local multiplexer guiServer browser
  for multiplexer in "T" "Z"; do
    for guiServer in "X" "W" "0"; do
      for browser in "F" "Z"; do
        local cfg="${BATS_TEST_TMPDIR}/cfg-${multiplexer}-${guiServer}-${browser}.yaml"
        _write_config "${cfg}" "${multiplexer}" "${guiServer}" "${browser}"
        _collect_entries "${cfg}" "${out}"
      done
    done
  done
  sort -u -o "${out}" "${out}"
}

# Read "name<TAB>path" pairs out of the committed .gitmodules.
function _committed_entries {
  awk '
    /^\[submodule "/ { name = $0; sub(/^\[submodule "/, "", name); sub(/"\]$/, "", name) }
    /^[[:space:]]*path = / { path = $3; if (name != "") print name "\t" path }
  ' "${GITMODULES}" | sort -u
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test ".gitmodules template exists" {
  [[ -f "${TEMPLATE}" ]]
}

# .gitmodules is generated per machine, so it holds a subset of the entries
# the template can emit. A name it does contain must agree on the path.
@test "every .gitmodules entry matches the template" {
  _require_chezmoi
  local rendered="${BATS_TEST_TMPDIR}/all-entries"
  _render_all_profiles "${rendered}"

  local failures=()
  while IFS=$'\t' read -r name path; do
    [[ -n "${name}" ]] || continue
    local expected
    expected="$(awk -F'\t' -v n="${name}" '$1 == n { print $2 }' "${rendered}")"
    if [[ -z "${expected}" ]]; then
      failures+=("${name}: in .gitmodules but the template never emits it")
    elif ! grep -qxF "${path}" <<< "${expected}"; then
      failures+=("${name}: .gitmodules says ${path}, template says ${expected}")
    fi
  done < <(_committed_entries)

  ((${#failures[@]} == 0)) || fail "$(printf '%s\n' "${failures[@]}")"
}

# Thunderbird profiles belong to the mail client: a machine can have one
# without a browser, and its company profiles can differ from the browser's.
@test "thunderbird submodules follow the mail client, not the browser" {
  _require_chezmoi
  local cfg="${BATS_TEST_TMPDIR}/cfg.yaml" entries="${BATS_TEST_TMPDIR}/entries"

  _write_config "${cfg}" "T" "X" "" "B"
  : > "${entries}"
  _collect_entries "${cfg}" "${entries}"
  run cut -f1 "${entries}"
  assert_line "thunderbird-personal"
  assert_line "thunderbird-enterprise-F1"
  refute_line --partial "firefox-"

  _write_config "${cfg}" "T" "X" "F" ""
  : > "${entries}"
  _collect_entries "${cfg}" "${entries}"
  run cut -f1 "${entries}"
  assert_line "firefox-personal"
  refute_line --partial "thunderbird-"
}

# A repository of its own the template names only on GitHub must be listed in
# the mirrors of dynet, or a checkout of it never gets its origin on GitLab.
# dybatpho lives on GitHub alone. The decrypting config renders no secret
# here: the machine `ci` has no company and no entry in the secrets.
@test "every submodule of the dotfiles has a mirror in the dynet mirrors" {
  _require_chezmoi
  local cfg="${BATS_TEST_TMPDIR}/cfg.yaml" rendered="${BATS_TEST_TMPDIR}/rendered"
  _write_config "${cfg}" "T" "X" "F"
  (
    cd "${DOTFILES_DIR}" || exit 1
    env HOME="${DOTFILES_REAL_HOME}" \
      XDG_CONFIG_HOME="${DOTFILES_REAL_XDG_CONFIG_HOME:-${DOTFILES_REAL_HOME}/.config}" \
      chezmoi --config "${cfg}" execute-template < "${TEMPLATE}" > "${rendered}"
    env HOME="${DOTFILES_REAL_HOME}" \
      XDG_CONFIG_HOME="${DOTFILES_REAL_XDG_CONFIG_HOME:-${DOTFILES_REAL_HOME}/.config}" \
      chezmoi --config "${cfg}" --source "${DOTFILES_DIR}/home" execute-template \
      < "${DOTFILES_DIR}/home/private_dot_config/dynet/mirrors.json.tmpl" \
      > "${rendered}.json"
  )
  local failures=() repository repositories mirrors
  repositories="$(sed -n 's|^ *url = https://github.com/\(dynamotn/.*\)\.git$|\1|p' "${rendered}")"
  mirrors="$(jq -r '.mirrors[].github' "${rendered}.json")"
  while read -r repository; do
    [[ "${repository}" != "dynamotn/dybatpho" ]] || continue
    grep -qxF "${repository}" <<< "${mirrors}" \
      || failures+=("${repository}: no mirror in dynet/mirrors.json")
  done <<< "${repositories}"

  ((${#failures[@]} == 0)) || fail "$(printf '%s\n' "${failures[@]}")"
}

# A submodule recorded in the index but missing from .gitmodules cannot be
# cloned by anyone else.
@test "every tracked submodule has a .gitmodules entry" {
  local failures=()
  while read -r path; do
    [[ -n "${path}" ]] || continue
    grep -qE "^[[:space:]]*path = ${path}$" "${GITMODULES}" \
      || failures+=("${path}: tracked as a submodule but absent from .gitmodules")
  done < <(cd "${DOTFILES_DIR}" && git ls-files --stage | awk '$1 == "160000" { print $4 }')

  ((${#failures[@]} == 0)) || fail "$(printf '%s\n' "${failures[@]}")"
}

# A pre-commit hook runs this suite with the repository being committed to
# exported as GIT_DIR and GIT_INDEX_FILE; left in place, every git call in a
# test reads -- or writes -- that repository instead of the one it means.
@test "the suite clears the repository-local git variables a hook exports" {
  local probe="${BATS_TEST_TMPDIR}/probe.bats"
  printf '%s\n' \
    "load '${DOTFILES_DIR}/scripts/test/test_helper'" \
    '@test "no git variable leaks in" { [[ -z "${GIT_DIR-}${GIT_INDEX_FILE-}${GIT_WORK_TREE-}" ]]; }' \
    > "${probe}"
  run env GIT_DIR=/nonexistent GIT_INDEX_FILE=/nonexistent/index GIT_WORK_TREE=/nonexistent \
    "${DOTFILES_DIR}/scripts/lib/dybatpho/test/lib/core/bin/bats" "${probe}"
  assert_success
}
