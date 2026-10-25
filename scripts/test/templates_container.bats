setup() {
  load test_helper
  setup_dotfiles_test_env
  command -v chezmoi &> /dev/null || skip "chezmoi not found"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# A template that reads the secrets is never rendered here: one naming the
# secrets submodule, the `decrypt` function or an age file. The `decrypt...`
# settings such as `.decryptPersonal` are plain booleans and do not count.
SECRET_PATTERN='secrets/data|[^.[:alnum:]_]decrypt([^[:alnum:]_]|$)|\.age([^[:alnum:]_]|$)'

#######################################
# @description Write a chezmoi config for a container profile
# @arg $1 string Path of the config to write
# @arg $2 string osid, such as linux-alpine
# @arg $3 string Init system, such as none
#######################################
function _write_container_config {
  local cfg osid init_system
  dybatpho::expect_args cfg osid init_system -- "$@"
  cat > "${cfg}" << EOF
sourceDir: "${DOTFILES_DIR}"
data:
  osid: "${osid}"
  kind: "container"
  initSystem: "${init_system}"
  bash: "/usr/bin/env bash"
  place: "cloud"
  code: "t00lb0x"
  company:
  decryptPersonal: false
  decryptEnterprise: []
  guiServer: "0"
  guiDriver: ""
  guiWinManager: ""
  languages: []
  browser: ""
  browserEnterpriseProfiles: []
  mailClient: ""
  mailEnterpriseProfiles: []
  terminalMultiplexer: "Z"
  hasSound: false
  hasBluetooth: false
  hasWifi: false
  preferGitSSH: false
  blockedGitlab: false
  darkMode: true
EOF
}

#######################################
# @description Render a template of the checkout as a Linux machine, with an
# empty home and the given config
# @arg $1 string Config written by _write_container_config
# @arg $2 string Template, relative to the checkout
# @arg $3 string Where to write the result
#######################################
function _render_linux {
  local cfg template output_path
  dybatpho::expect_args cfg template output_path -- "$@"
  local home="${BATS_TEST_TMPDIR}/empty-home"
  dybatpho::ensure_dir "${home}" > /dev/null
  (
    cd "${DOTFILES_DIR}" || exit 1
    env HOME="${home}" XDG_CONFIG_HOME="${home}/.config" \
      chezmoi --config "${cfg}" execute-template --source "${DOTFILES_DIR}" \
      --override-data '{"chezmoi":{"os":"linux","osRelease":{"idLike":""}}}' \
      < "${DOTFILES_DIR}/${template}" > "${output_path}"
  )
}

#######################################
# @description Render every hook and the ignore list for one profile, and
# check each rendered hook parses
# @arg $1 string osid
# @arg $2 string Init system
#######################################
function _assert_profile_renders {
  local osid init_system
  dybatpho::expect_args osid init_system -- "$@"
  local cfg="${BATS_TEST_TMPDIR}/${osid}.yaml"
  _write_container_config "${cfg}" "${osid}" "${init_system}"

  local -a failures=()
  local template relative rendered rendered_count=0
  for template in "${DOTFILES_DIR}"/home/.chezmoiscripts/*.tmpl "${DOTFILES_DIR}/home/.chezmoiignore.tmpl"; do
    relative="${template#"${DOTFILES_DIR}"/}"
    grep -qE "${SECRET_PATTERN}" "${template}" && continue
    rendered="${BATS_TEST_TMPDIR}/${osid}-$(basename "${template}" .tmpl)"
    if ! _render_linux "${cfg}" "${relative}" "${rendered}" 2> "${rendered}.err"; then
      failures+=("${relative}: $(cat "${rendered}.err")")
      continue
    fi
    rendered_count=$((rendered_count + 1))
    [[ "${relative}" == *.sh.tmpl ]] || continue
    bash -n "${rendered}" 2> "${rendered}.err" || failures+=("${relative}: $(cat "${rendered}.err")")
  done

  ((${#failures[@]} == 0)) || fail "$(printf '%s\n' "${failures[@]}")"
  # A pattern that skipped everything would pass without checking anything.
  ((rendered_count > 10))
}

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

@test "hooks render and parse in an Alpine container without an init system" {
  _assert_profile_renders linux-alpine none
}

@test "hooks render and parse in a Debian container without an init system" {
  _assert_profile_renders linux-debian none
}

@test "hooks render and parse in an Ubuntu container without an init system" {
  _assert_profile_renders linux-ubuntu none
}

@test "the secrets filter skips only templates that read the secrets" {
  run grep -lE "${SECRET_PATTERN}" "${DOTFILES_DIR}/home/.chezmoiignore.tmpl"
  assert_failure
  run grep -qE "${SECRET_PATTERN}" <<< '{{ include "x.age" | decrypt }}'
  assert_success
  run grep -qE "${SECRET_PATTERN}" <<< '{{ if .decryptPersonal }}'
  assert_failure
}

@test "the tool install hooks only warn with DOTFILES_SKIP_TOOLS=1" {
  local cfg="${BATS_TEST_TMPDIR}/alpine.yaml" rendered="${BATS_TEST_TMPDIR}/install.sh"
  _write_container_config "${cfg}" linux-alpine none
  local template
  for template in "${DOTFILES_DIR}"/home/.chezmoiscripts/run_onchange_after_02-install-*.tmpl; do
    DOTFILES_SKIP_TOOLS=1 _render_linux "${cfg}" "${template#"${DOTFILES_DIR}"/}" "${rendered}"
    run grep -c 'DOTFILES_SKIP_TOOLS is set' "${rendered}"
    assert_output 1
    run grep -E '^[^#]*/dytoy"? ' "${rendered}"
    assert_failure
  done
}

@test "each tool install hook hashes only the definitions of its method" {
  local cfg="${BATS_TEST_TMPDIR}/alpine.yaml" rendered="${BATS_TEST_TMPDIR}/install.sh"
  _write_container_config "${cfg}" linux-alpine none
  _render_linux "${cfg}" home/.chezmoiscripts/run_onchange_after_02-install-04-mise-tools.sh.tmpl "${rendered}"
  local definition name
  while IFS= read -r name; do
    definition="${DOTFILES_DIR}/home/.chezmoitemplates/dytoy/${name}"
    run grep -E '^[ -]*method:[[:space:]]*mise[[:space:]]*$' "${definition}"
    assert_success
  done < <(sed -n 's/^# \(.*\) hash: .*/\1/p' "${rendered}")
  run grep -c ' hash: ' "${rendered}"
  refute_output 0
}

# ---------------------------------------------------------------------------
# Hooks that meet a missing tool
# ---------------------------------------------------------------------------

#######################################
# @description Render a hook for an Alpine container and run it with a PATH
# that has the core utilities only
# @arg $1 string Hook template, relative to the checkout
#######################################
function _run_hook_without_tools {
  local template
  dybatpho::expect_args template -- "$@"
  local cfg="${BATS_TEST_TMPDIR}/alpine.yaml" rendered="${BATS_TEST_TMPDIR}/hook.sh"
  _write_container_config "${cfg}" linux-alpine none
  _render_linux "${cfg}" "${template}" "${rendered}"
  run env PATH="/usr/bin:/bin" "${BASH}" "${rendered}"
}

@test "the fish hook warns and succeeds where fish is missing" {
  [[ ! -x /usr/bin/fish && ! -x /bin/fish ]] || skip "fish is installed in /usr/bin or /bin"
  _run_hook_without_tools home/.chezmoiscripts/run_onchange_after_03-setup-fish.sh.tmpl
  assert_success
  assert_output --partial "fish is not installed"
}

@test "the neovim hook warns and succeeds where nvim is missing" {
  [[ ! -x /usr/bin/nvim && ! -x /bin/nvim ]] || skip "nvim is installed in /usr/bin or /bin"
  _run_hook_without_tools home/.chezmoiscripts/run_onchange_after_03-setup-nvim.sh.tmpl
  assert_success
  assert_output --partial "nvim is not installed"
}

@test "the rclone hook does nothing without an enterprise's secrets" {
  local cfg="${BATS_TEST_TMPDIR}/alpine.yaml" rendered="${BATS_TEST_TMPDIR}/rclone.sh"
  _write_container_config "${cfg}" linux-alpine none
  _render_linux "${cfg}" home/.chezmoiscripts/run_onchange_after_04-start_rclone.sh.tmpl "${rendered}"
  run grep -E 'rclone_conf|systemctl|rc-service' "${rendered}"
  assert_failure
}

# ---------------------------------------------------------------------------
# dytoy on a distribution it has no package method for
# ---------------------------------------------------------------------------

@test "dytoy maps Debian to the Ubuntu packages" {
  local cfg="${BATS_TEST_TMPDIR}/debian.yaml" rendered="${BATS_TEST_TMPDIR}/dytoy"
  _write_container_config "${cfg}" linux-debian none
  _render_linux "${cfg}" home/dot_local/bin/executable_dytoy.tmpl "${rendered}"
  run grep -E 'dytoy::install_ubuntu_package|package_manager::init_ubuntu' "${rendered}"
  assert_success
}

@test "dytoy hands the init system to the service helpers" {
  local cfg="${BATS_TEST_TMPDIR}/alpine.yaml" rendered="${BATS_TEST_TMPDIR}/dytoy"
  _write_container_config "${cfg}" linux-alpine none
  _render_linux "${cfg}" home/dot_local/bin/executable_dytoy.tmpl "${rendered}"
  run grep -x 'export DYTOY_INIT_SYSTEM="none"' "${rendered}"
  assert_success
}

@test "dytoy os skips an OS it has no package method for" {
  local cfg="${BATS_TEST_TMPDIR}/fedora.yaml" rendered="${BATS_TEST_TMPDIR}/dytoy"
  _write_container_config "${cfg}" linux-fedora none
  _render_linux "${cfg}" home/dot_local/bin/executable_dytoy.tmpl "${rendered}"
  bash -n "${rendered}"
  run bash "${rendered}" os --dry-run
  assert_success
  assert_output --partial "No package manager is known for linux-fedora"
}

@test "dytoy os skips without root, sudo or doas" {
  dybatpho::is_root && skip "runs as root"
  local cfg="${BATS_TEST_TMPDIR}/alpine.yaml" rendered="${BATS_TEST_TMPDIR}/dytoy"
  _write_container_config "${cfg}" linux-alpine none
  _render_linux "${cfg}" home/dot_local/bin/executable_dytoy.tmpl "${rendered}"
  # Every command of the usual PATH, except the two that grant root.
  local farm="${BATS_TEST_TMPDIR}/no-sudo-bin" dir command
  dybatpho::ensure_dir "${farm}" > /dev/null
  local -a path_dirs
  IFS=: read -r -a path_dirs <<< "${PATH}"
  for dir in "${path_dirs[@]}"; do
    for command in "${dir}"/*; do
      [[ -x "${command}" ]] || continue
      case "${command##*/}" in sudo | doas) continue ;; *) ;; esac
      [[ -e "${farm}/${command##*/}" ]] || ln -s "${command}" "${farm}/${command##*/}"
    done
  done

  run env PATH="${farm}" "${BASH}" "${rendered}" os --dry-run
  assert_success
  assert_output --partial "Neither root nor sudo or doas is available"
}
