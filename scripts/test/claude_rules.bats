# dyshellint disable=SC2154 DOTFILES_DIR, DOTFILES_REAL_* and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  CLAUDE_DIR="${DOTFILES_DIR}/home/private_dot_claude"
  ALL_TMPL="${DOTFILES_DIR}/home/.chezmoitemplates/ai/all.md.tmpl"
}

function _require_chezmoi {
  command -v chezmoi &> /dev/null || skip "chezmoi not found"
}

# Render the template $1 into the file $2.
function _render {
  (
    cd "${DOTFILES_DIR}" || exit 1
    env HOME="${DOTFILES_REAL_HOME}" \
      XDG_CONFIG_HOME="${DOTFILES_REAL_XDG_CONFIG_HOME:-${DOTFILES_REAL_HOME}/.config}" \
      chezmoi execute-template --source "${DOTFILES_DIR}" < "${1}" > "${2}"
  )
}

# Write the ai/ partials the templates $2... include into $1, sorted.
function _partials {
  local into="${1}"
  shift
  grep -ohE 'template "ai/[a-z-]+\.md\.tmpl"' "$@" > "${into}"
  sort -o "${into}" "${into}"
}

@test "Claude includes every partial of all.md exactly once" {
  local want="${BATS_TEST_TMPDIR}/want" got="${BATS_TEST_TMPDIR}/got"
  _partials "${want}" "${ALL_TMPL}"
  _partials "${got}" "${CLAUDE_DIR}/CLAUDE.md.tmpl" "${CLAUDE_DIR}"/rules/*.md.tmpl
  diff "${want}" "${got}" || fail "Claude's partials differ from all.md's"
}

@test "CLAUDE.md and every rule render under 200 lines" {
  _require_chezmoi
  local f out n
  for f in "${CLAUDE_DIR}/CLAUDE.md.tmpl" "${CLAUDE_DIR}"/rules/*.md.tmpl; do
    out="${BATS_TEST_TMPDIR}/$(basename "${f}" .tmpl)"
    _render "${f}" "${out}" || fail "render failed: ${f}"
    [[ -s "${out}" ]] || fail "rendered empty: ${f}"
    n=0
    while IFS= read -r _; do n=$((n + 1)); done < "${out}"
    ((n < 200)) || fail "${f} renders ${n} lines"
  done
}

@test "every section heading of all.md reaches Claude" {
  _require_chezmoi
  local f all claude="${BATS_TEST_TMPDIR}/claude.md" heading
  all="${BATS_TEST_TMPDIR}/all.md"
  _render "${ALL_TMPL}" "${all}"
  : > "${claude}"
  for f in "${CLAUDE_DIR}/CLAUDE.md.tmpl" "${CLAUDE_DIR}"/rules/*.md.tmpl; do
    _render "${f}" "${claude}.part"
    cat "${claude}.part" >> "${claude}"
  done
  grep -E '^#{1,2} ' "${all}" > "${all}.headings"
  while IFS= read -r heading; do
    grep -qxF -- "${heading}" "${claude}" || fail "heading lost for Claude: ${heading}"
  done < "${all}.headings"
}

@test "Codex gets the shell-scripts section as a skill, every other agent inline" {
  _require_chezmoi
  local codex="${BATS_TEST_TMPDIR}/codex.md" other="${BATS_TEST_TMPDIR}/other.md"
  local skill="${BATS_TEST_TMPDIR}/SKILL.md"
  _render "${DOTFILES_DIR}/home/private_dot_codex/AGENTS.md.tmpl" "${codex}"
  _render "${DOTFILES_DIR}/home/private_dot_config/AGENTS.md.tmpl" "${other}"
  _render "${DOTFILES_DIR}/home/dot_agents/skills/shell-scripts/SKILL.md.tmpl" "${skill}"
  run grep -qx '## Writing scripts' "${codex}"
  assert_failure
  grep -qF "load the \`shell-scripts\` skill" "${codex}"
  grep -qx '## Writing scripts' "${other}"
  grep -qx 'name: shell-scripts' "${skill}"
  grep -qx '## Writing scripts' "${skill}"
}

@test "the shell-scripts rule is scoped to shell files" {
  _require_chezmoi
  local out="${BATS_TEST_TMPDIR}/shell-scripts.md"
  _render "${CLAUDE_DIR}/rules/shell-scripts.md.tmpl" "${out}"
  local first fm="${BATS_TEST_TMPDIR}/frontmatter.yaml"
  read -r first < "${out}"
  [[ "${first}" == "---" ]]
  # The frontmatter parses as YAML and lists the globs under paths.
  sed -n '2,/^---$/{/^---$/d;p}' "${out}" > "${fm}"
  yq -e '.paths | length > 0' "${fm}" > /dev/null
  yq -e '.paths[] | select(. == "**/*.sh")' "${fm}" > /dev/null
  grep -qx '## Writing scripts' "${out}"
}
