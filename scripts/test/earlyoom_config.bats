# dyshellint disable=SC2154 DOTFILES_DIR, DOTFILES_REAL_* and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  command -v chezmoi &> /dev/null || skip "chezmoi not found"
  OUT="${BATS_TEST_TMPDIR}"
}

# Render the root source template $1 into $2, with the chezmoi data overridden by $3.
function _render {
  (
    cd "${DOTFILES_DIR}" || exit 1
    env HOME="${DOTFILES_REAL_HOME}" \
      XDG_CONFIG_HOME="${DOTFILES_REAL_XDG_CONFIG_HOME:-${DOTFILES_REAL_HOME}/.config}" \
      chezmoi execute-template --source "${DOTFILES_DIR}/root" --override-data "${3}" \
      --file "${DOTFILES_DIR}/root/${1}" > "${2}"
  )
}

# The argv earlyoom.service gets from $1: systemd strips the outer quotes of
# the value and splits $EARLYOOM_ARGS on whitespace, with no shell parsing.
function _systemd_argv {
  local value
  value="$(sed -n "s/^EARLYOOM_ARGS='\\(.*\\)'\$/\\1/p" "${1}")"
  [[ -n "${value}" ]] || return 1
  local -a words
  read -ra words <<< "${value}"
  printf '%s\n' "${words[@]}"
}

# The argv /etc/init.d/earlyoom gets from $1: the file is sourced by sh, and
# OpenRC evals command_args="${EARLYOOM_ARGS}".
function _openrc_argv {
  # dyshellint disable=SC2016 the inner script expands in sh, not here
  sh -c '. "$1" && eval "set -- ${EARLYOOM_ARGS}" && printf "%s\n" "$@"' sh "${1}"
}

@test "earlyoom gets the same arguments on systemd and OpenRC" {
  _render etc/default/earlyoom.tmpl "${OUT}/default" '{"initSystem":"systemd","kind":"pc"}'
  _render etc/conf.d/earlyoom.tmpl "${OUT}/confd" '{"initSystem":"openrc","kind":"pc"}'
  _systemd_argv "${OUT}/default" > "${OUT}/systemd.argv"
  _openrc_argv "${OUT}/confd" > "${OUT}/openrc.argv"
  run diff "${OUT}/systemd.argv" "${OUT}/openrc.argv"
  assert_success
}

@test "earlyoom prefers shellcheck and spares the session" {
  _render etc/default/earlyoom.tmpl "${OUT}/default" '{"initSystem":"systemd","kind":"pc"}'
  _systemd_argv "${OUT}/default" > "${OUT}/systemd.argv"
  local -a argv
  mapfile -t argv < "${OUT}/systemd.argv"
  local i prefer="" avoid=""
  for ((i = 0; i < ${#argv[@]} - 1; i++)); do
    [[ "${argv[i]}" != --prefer ]] || prefer="${argv[i + 1]}"
    [[ "${argv[i]}" != --avoid ]] || avoid="${argv[i + 1]}"
  done
  grep -qE "${prefer}" <<< shellcheck || fail "--prefer misses shellcheck: ${prefer}"
  ! grep -qE "${prefer}" <<< shellcheck-x || fail "--prefer is not anchored: ${prefer}"
  grep -qE "${avoid}" <<< niri || fail "--avoid misses niri: ${avoid}"
  ! grep -qE "${avoid}" <<< shellcheck || fail "--avoid spares shellcheck: ${avoid}"
}

@test "each init system gets only its own earlyoom file, and a container none" {
  _render etc/conf.d/earlyoom.tmpl "${OUT}/confd" '{"initSystem":"systemd","kind":"pc"}'
  [[ ! -s "${OUT}/confd" ]] || fail "systemd got etc/conf.d/earlyoom"
  _render etc/default/earlyoom.tmpl "${OUT}/default" '{"initSystem":"openrc","kind":"pc"}'
  [[ ! -s "${OUT}/default" ]] || fail "OpenRC got etc/default/earlyoom"
  _render etc/default/earlyoom.tmpl "${OUT}/default" '{"initSystem":"systemd","kind":"container"}'
  [[ ! -s "${OUT}/default" ]] || fail "a container got etc/default/earlyoom"
}
