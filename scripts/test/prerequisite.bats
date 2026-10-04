setup() {
  load test_helper
  setup_dotfiles_test_env
  [[ ! -e /opt/homebrew/bin/brew && ! -e /usr/local/bin/brew ]] \
    || skip "a real Homebrew is installed where the script looks first"

  BREW_PREFIX="${BATS_TEST_TMPDIR}/homebrew"
  BREW_LOG="${BATS_TEST_TMPDIR}/brew.log"
  mkdir -p "${BREW_PREFIX}/bin"
  : > "${BREW_LOG}"
  # macOS as `uname` reports it, and a sudo that grants everything at once.
  printf '#!/bin/sh\nprintf "Darwin\\n"\n' > "${HOME}/.local/bin/uname"
  printf '#!/bin/sh\nexit 0\n' > "${HOME}/.local/bin/sudo"
  chmod +x "${HOME}/.local/bin/uname" "${HOME}/.local/bin/sudo"
}

# Writes a fake `brew` at the prefix and on PATH, recording every call, whose
# `shellenv` exits with the given status.
# @arg $1 number Exit status of `brew shellenv`
function fake_brew {
  local shellenv_status
  dybatpho::expect_args shellenv_status -- "$@"
  cat > "${BREW_PREFIX}/bin/brew" << EOF
#!/bin/sh
printf '%s\n' "\$*" >> '${BREW_LOG}'
case "\$1" in
  --prefix) printf '%s\n' '${BREW_PREFIX}' ;;
  shellenv)
    [ ${shellenv_status} -eq 0 ] && printf 'export HOMEBREW_PREFIX=%s\n' '${BREW_PREFIX}'
    exit ${shellenv_status}
    ;;
esac
EOF
  chmod +x "${BREW_PREFIX}/bin/brew"
  ln -sf "${BREW_PREFIX}/bin/brew" "${HOME}/.local/bin/brew"
}

@test "prerequisite.sh loads the Homebrew environment on macOS and installs" {
  # The sudo keepalive's EXIT trap read its pid when the script ended, after
  # the local holding it was gone, so under `set -u` every run that kept sudo
  # alive ended with `sudo_pid: unbound variable` and status 1.
  fake_brew 0

  run --separate-stderr bash "${DOTFILES_DIR}/scripts/prerequisite.sh"
  assert_success
  grep -q '^install git curl openssh chezmoi age yq$' "${BREW_LOG}"
  grep -q 'brew shellenv' "${HOME}/.zprofile"
}
