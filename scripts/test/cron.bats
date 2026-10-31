# dyshellint disable=SC2154 DOTFILES_DIR and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/cron.sh"

  # A crontab kept in a file: absent means the user has none, and
  # CRONTAB_BROKEN makes `crontab -l` fail as it does without permission.
  export CRONTAB_FILE="${BATS_TEST_TMPDIR}/crontab"
  export CRONTAB_WRITES="${BATS_TEST_TMPDIR}/crontab-writes"
  cat > "${HOME}/.local/bin/crontab" << 'STUB'
#!/usr/bin/env bash
case "$1" in
  -l)
    if [[ -n "${CRONTAB_BROKEN:-}" ]]; then
      echo "crontab: Operation not permitted" >&2
      exit 1
    fi
    [[ -f "${CRONTAB_FILE}" ]] || { echo "crontab: no crontab for tester" >&2; exit 1; }
    cat "${CRONTAB_FILE}"
    ;;
  -)
    cat > "${CRONTAB_FILE}"
    echo write >> "${CRONTAB_WRITES}"
    ;;
esac
STUB
  chmod +x "${HOME}/.local/bin/crontab"
}

@test "cron::set_block creates the crontab when the user has none" {
  run cron::set_block sample <<< '0 12 * * * true'
  assert_success
  run cat "${CRONTAB_FILE}"
  assert_output $'# BEGIN dotfiles:sample\n0 12 * * * true\n# END dotfiles:sample'
}

@test "cron::set_block replaces its block and keeps the other lines" {
  printf '%s\n' 'MAILTO=""' '# BEGIN dotfiles:sample' 'old' '# END dotfiles:sample' '5 * * * * mine' > "${CRONTAB_FILE}"
  run cron::set_block sample <<< 'new'
  assert_success
  run cat "${CRONTAB_FILE}"
  assert_output $'MAILTO=""\n5 * * * * mine\n# BEGIN dotfiles:sample\nnew\n# END dotfiles:sample'
}

@test "cron::set_block removes its block on empty input" {
  printf '%s\n' '5 * * * * mine' '# BEGIN dotfiles:sample' 'old' '# END dotfiles:sample' > "${CRONTAB_FILE}"
  run cron::set_block sample < /dev/null
  assert_success
  run cat "${CRONTAB_FILE}"
  assert_output '5 * * * * mine'
}

@test "cron::set_block does not rewrite an unchanged crontab" {
  printf '%s\n' '# BEGIN dotfiles:sample' 'same' '# END dotfiles:sample' > "${CRONTAB_FILE}"
  run cron::set_block sample <<< 'same'
  assert_success
  assert [ ! -e "${CRONTAB_WRITES}" ]
}

@test "cron::set_block leaves the crontab alone when it cannot be read" {
  printf '%s\n' '5 * * * * mine' > "${CRONTAB_FILE}"
  export CRONTAB_BROKEN=1
  run cron::set_block sample <<< 'new'
  assert_failure
  assert_output --partial 'Operation not permitted'
  assert [ ! -e "${CRONTAB_WRITES}" ]
}
