# dyshellint disable=SC2154 DOTFILES_DIR and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  DYTOY_DIR="${DOTFILES_DIR}/home/.chezmoitemplates/dytoy"
  DOC_FILE="${DOTFILES_DIR}/docs/dytoy.md"
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/dytoy_docs.sh"
  WITH="${BATS_TEST_TMPDIR}/browser.yaml.tmpl"
  cat > "${WITH}" << 'EOT'
{{- /* doc
name: firefox
description: Web browser
category: Browsers
subcategory: GUI
*/ -}}
{{- /* doc
name: zen
description: "Calm: `fast` browser"
category: Browsers
subcategory: GUI
*/ -}}
{{- if eq .os "linux" }}
firefox:
  repo: mozilla/firefox
{{- end }}
EOT
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Every OWNER/REPO named inside a `github:` or `gitlab:` block of a tool
# definition. Other `repo:` keys (package overlays, brew taps) live outside
# those blocks and are not links to a project page.
function _defined_repos {
  local repos
  repos="$(awk '
    FNR == 1 { inblock = 0 }
    /^(github|gitlab):[[:space:]]*$/ { inblock = 1; next }
    /^[^[:space:]{]/ { inblock = 0 }
    inblock && /^[[:space:]]+repo:[[:space:]]/ { print $2 }
  ' "${DYTOY_DIR}"/*.yaml "${DYTOY_DIR}"/*.yaml.tmpl)"
  sort -u <<< "${repos,,}"
}

# Every OWNER/REPO the documentation links to on github.com or gitlab.com.
function _documented_repos {
  local links
  links="$(grep -oE '(github|gitlab)\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+' "${DOC_FILE}")"
  links="$(sed -E 's#^(github|gitlab)\.com/##' <<< "${links}")"
  sort -u <<< "${links,,}"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "dytoy documentation exists" {
  [[ -f "${DOC_FILE}" ]]
}

# A tool whose definition points at one project while the docs link another
# sends the reader to the wrong place, which is how stale forks and renamed
# repositories survive unnoticed.
@test "every tool definition is linked from docs/dytoy.md" {
  local documented defined
  documented="$(_documented_repos)"
  defined="$(_defined_repos)"

  local failures=()
  while read -r repo; do
    [[ -n "${repo}" ]] || continue
    grep -qxF "${repo}" <<< "${documented}" \
      || failures+=("${repo}: installed by dytoy but not linked in docs/dytoy.md")
  done <<< "${defined}"

  ((${#failures[@]} == 0)) || fail "$(printf '%s\n' "${failures[@]}")"
}

@test "blocks prints one document per block" {
  run dytoy_docs::blocks "${WITH}"
  assert_success
  local docs="${output}"
  run yq ea '[.name] | join(",")' <<< "${docs}"
  assert_output "firefox,zen"
  run yq ea '[.file] | join(",")' <<< "${docs}"
  assert_output "browser.yaml.tmpl,browser.yaml.tmpl"
}

@test "blocks prints nothing without a block" {
  printf 'firefox:\n  repo: a/b\n' > "${BATS_TEST_TMPDIR}/plain.yaml"
  run dytoy_docs::blocks "${BATS_TEST_TMPDIR}/plain.yaml"
  assert_success
  assert_output ""
}

@test "strip removes blocks and keeps the rest byte-identical" {
  cat > "${BATS_TEST_TMPDIR}/expected" << 'EOT'
{{- if eq .os "linux" }}
firefox:
  repo: mozilla/firefox
{{- end }}
EOT
  dytoy_docs::strip "${WITH}" > "${BATS_TEST_TMPDIR}/got"
  run dytoy_docs::strip "${WITH}"
  assert_output "$(< "${BATS_TEST_TMPDIR}/expected")"
  run cmp "${BATS_TEST_TMPDIR}/got" "${BATS_TEST_TMPDIR}/expected"
  assert_success
}

@test "unclosed block dies naming the file" {
  printf '{{- /* doc\nname: x\nfirefox:\n' > "${BATS_TEST_TMPDIR}/open.yaml"
  run dytoy_docs::strip "${BATS_TEST_TMPDIR}/open.yaml"
  assert_failure
  assert_output --partial "open.yaml"
  run dytoy_docs::blocks "${BATS_TEST_TMPDIR}/open.yaml"
  assert_failure
  assert_output --partial "open.yaml"
}

@test "opener after definition text is not a block" {
  printf 'firefox:\n  repo: a/b\n{{- /* doc\nname: x\n*/ -}}\n' > "${BATS_TEST_TMPDIR}/late.yaml"
  run dytoy_docs::blocks "${BATS_TEST_TMPDIR}/late.yaml"
  assert_success
  assert_output ""
  run dytoy_docs::strip "${BATS_TEST_TMPDIR}/late.yaml"
  assert_success
  assert_output "$(< "${BATS_TEST_TMPDIR}/late.yaml")"
}
