setup() {
  load test_helper
  DYTOY_DIR="${DOTFILES_DIR}/home/.chezmoitemplates/dytoy"
  DOC_FILE="${DOTFILES_DIR}/docs/dytoy.md"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Every OWNER/REPO named inside a `github:` or `gitlab:` block of a tool
# definition. Other `repo:` keys (package overlays, brew taps) live outside
# those blocks and are not links to a project page.
function _defined_repos {
  awk '
    FNR == 1 { inblock = 0 }
    /^(github|gitlab):[[:space:]]*$/ { inblock = 1; next }
    /^[^[:space:]{]/ { inblock = 0 }
    inblock && /^[[:space:]]+repo:[[:space:]]/ { print $2 }
  ' "${DYTOY_DIR}"/*.yaml "${DYTOY_DIR}"/*.yaml.tmpl \
    | tr '[:upper:]' '[:lower:]' | sort -u
}

# Every OWNER/REPO the documentation links to on github.com or gitlab.com.
function _documented_repos {
  grep -oE '(github|gitlab)\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+' "${DOC_FILE}" \
    | sed -E 's#^(github|gitlab)\.com/##' \
    | tr '[:upper:]' '[:lower:]' | sort -u
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "dytoy documentation exists" {
  [ -f "${DOC_FILE}" ]
}

# A tool whose definition points at one project while the docs link another
# sends the reader to the wrong place, which is how stale forks and renamed
# repositories survive unnoticed.
@test "every tool definition is linked from docs/dytoy.md" {
  local documented
  documented="$(_documented_repos)"

  local failures=()
  while read -r repo; do
    [ -n "${repo}" ] || continue
    grep -qxF "${repo}" <<< "${documented}" \
      || failures+=("${repo}: installed by dytoy but not linked in docs/dytoy.md")
  done < <(_defined_repos)

  ((${#failures[@]} == 0)) || fail "$(printf '%s\n' "${failures[@]}")"
}
