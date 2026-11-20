# dyshellint disable=SC2154 DOTFILES_DIR and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  dybatpho::is command chezmoi || skip "chezmoi is not installed"
  HOOK="${BATS_TEST_TMPDIR}/remove-unchosen.sh"
  IGNORE="${BATS_TEST_TMPDIR}/chezmoiignore"
  render_template "home/.chezmoiscripts/run_onchange_after_06-remove-unchosen.sh.tmpl" "${HOOK}"
  render_template "home/.chezmoiignore.tmpl" "${IGNORE}"
}

@test "the remove-unchosen hook only removes what chezmoi does not apply here" {
  run "${BASH}" -n "${HOOK}"
  assert_success
  local line path checked=0
  while IFS= read -r line; do
    [[ "${line}" == "dybatpho::safe_rm "* ]] || continue
    path="${line##* \"}"
    path="${path%\"}"
    path="${path#"${DOTFILES_REAL_HOME}/"}"
    # Ignored itself, or inside an ignored directory.
    grep -qxF -e "${path}" -e "${path%/*}" "${IGNORE}" \
      || fail "${path} is removed although chezmoi applies it"
    [[ "${path}" != *profiles* && "${path}" != .mozilla* && "${path}" != .zen* ]] \
      || fail "${path} holds data, not config"
    checked=$((checked + 1))
  done < "${HOOK}"
  ((checked > 0))
}

@test "the remove-unchosen hook removes a leftover and keeps the rest of the home" {
  mkdir -p "${HOME}/.config/niri" "${HOME}/.config/kept"
  # The rendered paths are of the real home: run it against the test home.
  sed "/^dybatpho::safe_rm/s|${DOTFILES_REAL_HOME}/|${HOME}/|" "${HOOK}" > "${HOOK}.test"
  grep -q "${HOME}/.config/niri" "${HOOK}.test" || skip "this machine chose niri"
  run "${BASH}" "${HOOK}.test"
  assert_success
  assert [ ! -e "${HOME}/.config/niri" ]
  assert [ -d "${HOME}/.config/kept" ]
}
