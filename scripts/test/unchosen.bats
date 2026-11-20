# dyshellint disable=SC2154 DOTFILES_DIR and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  dybatpho::is command chezmoi || skip "chezmoi is not installed"
  HOOK_TEMPLATE="home/.chezmoiscripts/run_onchange_after_06-remove-unchosen.sh.tmpl"
}

# Render a template for a machine that chose the given window manager, so the
# result does not depend on the machine running the test.
# @arg $1 string Window manager code, as in choices.yaml
# @arg $2 string Template, relative to the repository
# @arg $3 string Where to write it
function _render_for {
  local manager template output_path
  manager="$1"
  template="$2"
  output_path="$3"
  local cfg="${BATS_TEST_TMPDIR}/wm-${manager:-none}.yaml" home="${BATS_TEST_TMPDIR}/empty-home"
  yq ".sourceDir = \"${DOTFILES_DIR}\" | .data.guiWinManager = \"${manager}\"" \
    "${DOTFILES_DIR}/scripts/test/fixtures/chezmoi.yaml" > "${cfg}"
  mkdir -p "${home}"
  (
    cd "${DOTFILES_DIR}" || exit 1
    env HOME="${home}" XDG_CONFIG_HOME="${home}/.config" \
      chezmoi --config "${cfg}" execute-template --source "${DOTFILES_DIR}" \
      < "${DOTFILES_DIR}/${template}" > "${output_path}"
  )
}

# Print the paths a rendered hook removes, relative to the home.
# @arg $1 string Rendered hook
function _removed {
  sed -n 's|^dybatpho::safe_rm --force --recursive ".*/empty-home/\(.*\)"$|\1|p' "$1"
}

@test "the remove-unchosen hook keeps the config of the window manager that was chosen" {
  local manager kept hook="${BATS_TEST_TMPDIR}/hook.sh"
  # Each manager with a path of its own config, which must stay.
  for manager in H:.config/hypr N:.config/niri A:.config/aerospace O:.config/omniwm; do
    kept="${manager#*:}"
    _render_for "${manager%%:*}" "${HOOK_TEMPLATE}" "${hook}"
    run "${BASH}" -n "${hook}"
    assert_success
    run _removed "${hook}"
    refute_line "${kept}"
    # The config of the others goes.
    [[ "${kept}" == ".config/niri" ]] || assert_line ".config/niri"
    [[ "${kept}" == ".config/omniwm" ]] || assert_line ".config/omniwm"
  done
}

@test "the remove-unchosen hook removes nothing chezmoi applies, and no data" {
  local manager path hook="${BATS_TEST_TMPDIR}/hook.sh" ignore="${BATS_TEST_TMPDIR}/ignore"
  for manager in H N A O G ""; do
    _render_for "${manager}" "${HOOK_TEMPLATE}" "${hook}"
    _render_for "${manager}" "home/.chezmoiignore.tmpl" "${ignore}"
    run _removed "${hook}"
    assert_success
    [[ -n "${output}" ]] || fail "no path removed for window manager '${manager}'"
    while IFS= read -r path; do
      # Ignored itself, or inside an ignored directory.
      grep -qxF -e "${path}" -e "${path%/*}" "${ignore}" \
        || fail "${path} is removed although chezmoi applies it with '${manager}'"
      [[ "${path}" == .config/* || "${path}" == ".wayland_init.fish" ]] \
        || fail "${path} is outside the config this repository writes"
    done <<< "${output}"
  done
}

@test "the remove-unchosen hook removes a leftover and keeps the rest of the home" {
  local hook="${BATS_TEST_TMPDIR}/hook.sh"
  _render_for H "${HOOK_TEMPLATE}" "${hook}"
  mkdir -p "${HOME}/.config/niri" "${HOME}/.config/hypr" "${HOME}/.config/kept"
  sed "/^dybatpho::safe_rm/s|\"[^\"]*/empty-home/|\"${HOME}/|" "${hook}" > "${hook}.test"
  run "${BASH}" "${hook}.test"
  assert_success
  assert [ ! -e "${HOME}/.config/niri" ]
  assert [ -d "${HOME}/.config/hypr" ]
  assert [ -d "${HOME}/.config/kept" ]
}
