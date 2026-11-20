# dyshellint disable=SC2154 DOTFILES_DIR and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  dybatpho::is command chezmoi || skip "chezmoi is not installed"
}

# Render the Mozilla externals for a machine with a mail client.
# @arg $1 string A yq update of the test config, such as `.data.darkMode = false`
function _render_mozilla {
  local cfg="${BATS_TEST_TMPDIR}/config.yaml" home="${BATS_TEST_TMPDIR}/empty-home"
  yq ".sourceDir = \"${DOTFILES_DIR}\" | .data.mailClient = \"T\" | $1" \
    "${DOTFILES_DIR}/scripts/test/fixtures/chezmoi.yaml" > "${cfg}"
  mkdir -p "${home}"
  cd "${DOTFILES_DIR}" || return 1
  run --separate-stderr env HOME="${home}" XDG_CONFIG_HOME="${home}/.config" \
    chezmoi --config "${cfg}" execute-template --source "${DOTFILES_DIR}" \
    < "${DOTFILES_DIR}/home/.chezmoiexternals/mozilla.yaml.tmpl"
}

@test "Thunderbird gets the Catppuccin flavour of the machine, under its add-on ID" {
  _render_mozilla '.data.darkMode = true'
  assert_success
  assert_line --partial '{d3f3abb5-21aa-57fd-80e3-a9a1887b1d16}.xpi:'
  assert_line --partial 'themes/macchiato/macchiato-teal.xpi'
  _render_mozilla '.data.darkMode = false'
  assert_success
  assert_line --partial '{85d64947-5410-5a95-8967-886c5a613ce3}.xpi:'
  assert_line --partial 'themes/latte/latte-teal.xpi'
  refute_output --partial 'macchiato'
}

@test "an accent with no known add-on ID stops the render" {
  _render_mozilla '.data.catppuccin.variant = "pink"'
  assert_failure
  assert_stderr --partial 'no add-on ID for the Thunderbird theme catppuccin-macchiato-pink'
}

@test "chezmoi reads every external as rendered for a machine" {
  local cfg="${BATS_TEST_TMPDIR}/config.yaml" home="${BATS_TEST_TMPDIR}/empty-home"
  local source="${BATS_TEST_TMPDIR}/source" template name
  yq ".sourceDir = \"${DOTFILES_DIR}\" | .data.mailClient = \"T\"" \
    "${DOTFILES_DIR}/scripts/test/fixtures/chezmoi.yaml" > "${cfg}"
  mkdir -p "${home}" "${source}/.chezmoiexternals" "${BATS_TEST_TMPDIR}/destination"
  cd "${DOTFILES_DIR}" || fail "no repository"
  for template in home/.chezmoiexternals/*.tmpl; do
    name="${template##*/}"
    # The real home: the Mozilla externals name the source relative to it.
    env HOME="${DOTFILES_REAL_HOME}" XDG_CONFIG_HOME="${home}/.config" \
      chezmoi --config "${cfg}" execute-template --source "${DOTFILES_DIR}" \
      < "${template}" > "${source}/.chezmoiexternals/${name%.tmpl}" \
      || fail "${name} does not render"
  done
  # A bare digest renders as valid YAML yet stops every apply.
  : > "${BATS_TEST_TMPDIR}/empty.yaml"
  run --separate-stderr chezmoi --config "${BATS_TEST_TMPDIR}/empty.yaml" --source "${source}" \
    --destination "${BATS_TEST_TMPDIR}/destination" \
    --persistent-state "${BATS_TEST_TMPDIR}/state.boltdb" managed
  assert_success
}
