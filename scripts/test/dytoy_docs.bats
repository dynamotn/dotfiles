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

# Write a definition $1 (file name) under DEFS with the given doc block body $2
# and definition text $3.
function _def {
  printf '{{- /* doc\n%s\n*/ -}}\n%s\n' "${2}" "${3}" > "${DEFS}/${1}"
}

# A small tree of definitions, an extra file and a categories file covering
# every row shape: default and explicit url, `url: none`, label, order.
function _docs_fixture {
  DEFS="${BATS_TEST_TMPDIR}/defs"
  EXTRA="${BATS_TEST_TMPDIR}/extra.yaml"
  CATS="${BATS_TEST_TMPDIR}/categories.yaml"
  mkdir -p "${DEFS}"
  cat > "${CATS}" << 'EOT'
- category: A
  subcategories: [x, y]
- category: B
  subcategories: [z]
- category: C
  subcategories: [w]
EOT
  # dyshellint disable=SC2016 the backticks are literal markdown, not a command
  _def tool.yaml.tmpl 'name: tool
description: "Tool `grep`: faster"
category: A
subcategory: y' 'name: tool
method: binary
github:
  repo: o/tool'
  _def rg.yaml.tmpl 'name: rg
label: ripgrep
description: a | b
category: A
subcategory: x
order: 20' 'name: rg
method: binary
github:
  repo: BurntSushi/ripgrep'
  _def fd.yaml 'name: fd
url: https://example.com/fd
description: Find files
category: A
subcategory: x
order: 10' 'name: fd
method: mise'
  _def aa.yaml 'name: aa
description: No order
category: A
subcategory: x' 'name: aa
method: binary
github:
  repo: o/aa'
  _def ssh.yaml 'name: ssh
url: none
description: SSH client
category: B
subcategory: z' 'name: ssh
method: os'
  cat > "${EXTRA}" << 'EOT'
- name: drivers
  label: GPU drivers
  url: none
  description: Graphics drivers
  category: B
  subcategory: z
  order: 5
EOT
}

# Run collect over the fixture and render its result into `output`.
function _generate {
  local json
  json="$(dytoy_docs::collect "${DEFS}" "${EXTRA}" "${CATS}")" || return
  dytoy_docs::render "${CATS}" <<< "${json}"
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

@test "url defaults to the github repo" {
  _docs_fixture
  run _generate
  assert_success
  assert_line '|[aa](https://github.com/o/aa)|No order|'
}

@test "label overrides name in the link text" {
  _docs_fixture
  run _generate
  assert_success
  assert_line --partial '|[ripgrep](https://github.com/BurntSushi/ripgrep)|'
}

@test "url none renders a plain cell" {
  _docs_fixture
  run _generate
  assert_success
  # dyshellint disable=SC2016 the backticks are literal markdown, not a command
  assert_line '|`ssh`|SSH client|'
}

@test "rows sort by subcategory then order then label" {
  _docs_fixture
  _def bb.yaml 'name: bb
description: Also no order
category: A
subcategory: x' 'name: bb
method: binary
github:
  repo: o/bb'
  _def Ab.yaml 'name: Ab
description: Capital
category: A
subcategory: x' 'name: Ab
method: binary
github:
  repo: o/Ab'
  run _generate
  assert_success
  local rows
  rows="$(grep -oE '^\|\[[^]]+\]' <<< "${output}")"
  assert_equal "${rows//$'\n'/,}" '|[fd],|[ripgrep],|[aa],|[Ab],|[bb],|[tool]'
}

@test "extra entries merge into their category" {
  _docs_fixture
  run _generate
  assert_success
  local section plain
  section="$(sed -n '/^## B$/,/^## /p' <<< "${output}")"
  plain="$(grep '^|`' <<< "${section}")"
  # dyshellint disable=SC2016 the backticks are literal markdown, not a command
  assert_equal "${plain}" '|`GPU drivers`|Graphics drivers|
|`ssh`|SSH client|'
}

@test "unknown subcategory dies" {
  _docs_fixture
  _def bad.yaml 'name: bad
description: Bad
category: A
subcategory: nope' 'name: bad
method: os'
  run _generate
  assert_failure
  assert_output --partial 'bad.yaml'
  assert_output --partial 'subcategory'
}

@test "duplicate name across files dies" {
  _docs_fixture
  _def again.yaml 'name: fd
url: none
description: Again
category: A
subcategory: x' 'name: fd
method: os'
  run _generate
  assert_failure
  assert_output --partial 'fd.yaml'
  assert_output --partial 'again.yaml'
}

@test "name without matching definition dies" {
  _docs_fixture
  _def typo.yaml 'name: tpyo
url: none
description: Typo
category: A
subcategory: x' 'name: typo
method: os'
  run _generate
  assert_failure
  assert_output --partial 'typo.yaml'
  assert_output --partial 'tpyo'
}

@test "render escapes pipe" {
  _docs_fixture
  run _generate
  assert_success
  assert_line '|[ripgrep](https://github.com/BurntSushi/ripgrep)|a \| b|'
}

@test "description with colon and backticks round-trips" {
  _docs_fixture
  run _generate
  assert_success
  # dyshellint disable=SC2016 the backticks are literal markdown, not a command
  assert_line '|[tool](https://github.com/o/tool)|Tool `grep`: faster|'
}

@test "empty category emits no heading" {
  _docs_fixture
  run _generate
  assert_success
  refute_line '## C'
  assert_line --index 0 '<!-- dytoy:begin (generated by scripts/dytoy_docs.sh, do not edit) -->'
  assert_line '## A'
  assert_line '## B'
  assert_equal "${lines[-1]}" '<!-- dytoy:end -->'
}
