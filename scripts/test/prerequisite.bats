setup() {
  load test_helper
  setup_dotfiles_test_env
  PREREQUISITE="${DOTFILES_DIR}/scripts/prerequisite.sh"
  CALL_LOG="${BATS_TEST_TMPDIR}/calls.log"
  # By absolute path: the Linux tests run it with a PATH of fakes only.
  SH_BIN="$(command -v sh)"
  # The fakes log the DEBIAN_FRONTEND they see; GitHub runners export one.
  unset DEBIAN_FRONTEND
  : > "${CALL_LOG}"
}

# Prepares the macOS tests, which run the real `grep` and so keep the PATH.
function setup_macos {
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

# Builds a PATH holding nothing but fakes, so the package manager the script
# finds is the one the test names, never the one of the host running it.
# @arg $1 number User id `id -u` reports
# @set FAKE_BIN The directory, to be used as the whole PATH
function setup_linux {
  local uid
  dybatpho::expect_args uid -- "$@"
  FAKE_BIN="${BATS_TEST_TMPDIR}/fake-bin"
  mkdir -p "${FAKE_BIN}"
  printf '#!/bin/sh\nprintf "Linux\\n"\n' > "${FAKE_BIN}/uname"
  printf '#!/bin/sh\nprintf "%s\\n"\n' "${uid}" > "${FAKE_BIN}/id"
  chmod +x "${FAKE_BIN}/uname" "${FAKE_BIN}/id"
  local tool
  for tool in env sleep; do
    ln -s "$(command -v "${tool}")" "${FAKE_BIN}/${tool}"
  done
}

# Writes a fake command into FAKE_BIN that records its name, the
# DEBIAN_FRONTEND it saw, and its arguments.
# @arg $1 string Command name
function fake_command {
  local name
  dybatpho::expect_args name -- "$@"
  cat > "${FAKE_BIN}/${name}" << EOF
#!/bin/sh
printf '%s [%s] %s\n' '${name}' "\${DEBIAN_FRONTEND:-}" "\$*" >> '${CALL_LOG}'
EOF
  chmod +x "${FAKE_BIN}/${name}"
}

# Writes a fake sudo that grants its timestamp calls and records then runs
# every other command.
function fake_sudo {
  cat > "${FAKE_BIN}/sudo" << EOF
#!/bin/sh
case "\$1" in -v | -n) exit 0 ;; esac
printf 'sudo %s\n' "\$*" >> '${CALL_LOG}'
exec "\$@"
EOF
  chmod +x "${FAKE_BIN}/sudo"
}

@test "prerequisite.sh is POSIX sh, so it runs before bash is installed" {
  run head -1 "${PREREQUISITE}"
  assert_output "#!/bin/sh"
  if command -v dash > /dev/null; then
    run dash -n "${PREREQUISITE}"
    assert_success
  fi
}

@test "prerequisite.sh loads the Homebrew environment on macOS and installs" {
  # The sudo keepalive's EXIT trap read its pid when the script ended, after
  # the local holding it was gone, so under `set -u` every run that kept sudo
  # alive ended with `sudo_pid: unbound variable` and status 1.
  setup_macos
  fake_brew 0

  run --separate-stderr sh "${PREREQUISITE}"
  assert_success
  grep -q '^install git curl openssh chezmoi age yq jq$' "${BREW_LOG}"
  grep -q 'brew shellenv' "${HOME}/.zprofile"
}

@test "prerequisite.sh stops on macOS when brew shellenv fails" {
  # The environment was sourced through a process substitution, whose status
  # is lost: a failing `brew shellenv` read as an empty environment, and the
  # script went on to install everything without Homebrew on its PATH.
  setup_macos
  fake_brew 1

  run --separate-stderr sh "${PREREQUISITE}"
  assert_failure
  assert_stderr --partial "brew shellenv"
  refute grep -q '^install' "${BREW_LOG}"
}

@test "prerequisite.sh installs on Debian as root without sudo or a debconf prompt" {
  # A container image runs as root and often has no sudo at all: every call
  # went through `sudo`, which failed with `sudo: not found`.
  setup_linux 0
  fake_command apt-get

  run env PATH="${FAKE_BIN}" "${SH_BIN}" "${PREREQUISITE}"
  assert_success
  run cat "${CALL_LOG}"
  assert_line "apt-get [noninteractive] update"
  assert_line --partial "apt-get [noninteractive] install -y ca-certificates git curl openssh-client bash jq"
  refute_output --partial "sudo"
}

@test "prerequisite.sh installs on Fedora through sudo" {
  setup_linux 1000
  fake_sudo
  fake_command dnf

  run env PATH="${FAKE_BIN}" "${SH_BIN}" "${PREREQUISITE}"
  assert_success
  run cat "${CALL_LOG}"
  assert_line "sudo dnf install -y ca-certificates git curl openssh-clients bash jq"
  assert_line --partial "dnf [] install -y"
}

@test "prerequisite.sh upgrades Arch in one transaction with the install" {
  # `pacman -Sy` followed by an install is a partial upgrade.
  setup_linux 0
  fake_command pacman

  run env PATH="${FAKE_BIN}" "${SH_BIN}" "${PREREQUISITE}"
  assert_success
  run cat "${CALL_LOG}"
  assert_output "pacman [] -Syu --needed --noconfirm ca-certificates git curl openssh bash jq"
}

@test "prerequisite.sh installs bash on Alpine" {
  setup_linux 0
  fake_command apk

  run env PATH="${FAKE_BIN}" "${SH_BIN}" "${PREREQUISITE}"
  assert_success
  run cat "${CALL_LOG}"
  assert_line "apk [] add --no-cache ca-certificates coreutils grep bash"
}

@test "prerequisite.sh stops when neither root nor able to escalate" {
  setup_linux 1000
  fake_command apk

  run --separate-stderr env PATH="${FAKE_BIN}" "${SH_BIN}" "${PREREQUISITE}"
  assert_failure
  assert_stderr --partial "neither sudo nor doas"
  run cat "${CALL_LOG}"
  assert_output ""
}
