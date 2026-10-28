# dyshellint disable=SC2154 DOTFILES_DIR and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  NOTIFY="${DOTFILES_DIR}/root/usr/local/bin/executable_notify-desktop"
  BACKUP="${DOTFILES_DIR}/root/etc/cron.daily/executable_restic-backup"
  FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
  CALL_LOG="${BATS_TEST_TMPDIR}/calls"
  RUN_DIR="${BATS_TEST_TMPDIR}/run"
  mkdir -p "${FAKE_BIN}" "${RUN_DIR}"
  : > "${CALL_LOG}"
  local name
  for name in logger runuser restic; do
    _fake_command "${name}"
  done
  # id -nu <uid> answers a user name for any uid.
  cat > "${FAKE_BIN}/id" << 'EOF'
#!/bin/sh
echo "user$2"
EOF
  chmod +x "${FAKE_BIN}/id"
}

# Write a stand-in for command $1 that logs its arguments to CALL_LOG.
function _fake_command {
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\n' "$1" "${CALL_LOG}" > "${FAKE_BIN}/${1}"
  chmod +x "${FAKE_BIN}/${1}"
}

# Create a session bus socket for uid $1 under RUN_DIR.
function _fake_bus {
  mkdir -p "${RUN_DIR}/${1}"
  python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "${RUN_DIR}/${1}/bus"
}

@test "notify-desktop turns a smartd warning into a critical notification for each bus" {
  command -v python3 &> /dev/null || skip "python3 not found"
  _fake_bus 1000

  run env PATH="${FAKE_BIN}:/usr/bin:/bin" NOTIFY_DESKTOP_RUN_DIR="${RUN_DIR}" \
    SMARTD_DEVICE=/dev/sda SMARTD_FAILTYPE=Health SMARTD_MESSAGE="SMART says the disk fails" \
    bash "${NOTIFY}"
  assert_success
  run cat "${CALL_LOG}"
  assert_line --partial "logger --tag notify-desktop -- Disk /dev/sda: Health: SMART says the disk fails"
  local bus="unix:path=${RUN_DIR}/1000/bus"
  assert_line --partial "runuser -u user1000 -- env -i PATH=/usr/bin:/bin DBUS_SESSION_BUS_ADDRESS=${bus} notify-send"
  assert_line --partial "--urgency=critical"
}

@test "notify-desktop only logs when no user has a session bus" {
  run env PATH="${FAKE_BIN}:/usr/bin:/bin" NOTIFY_DESKTOP_RUN_DIR="${RUN_DIR}" \
    bash "${NOTIFY}" normal "Backup done"
  assert_success
  run cat "${CALL_LOG}"
  assert_line "logger --tag notify-desktop -- Backup done: "
  refute_output --partial "runuser"
}

@test "notify-desktop refuses to run without a summary" {
  run env PATH="${FAKE_BIN}:/usr/bin:/bin" bash "${NOTIFY}" critical
  assert_failure
}

@test "restic-backup only logs until the env file exists" {
  run env PATH="${FAKE_BIN}:/usr/bin:/bin" RESTIC_ENV_FILE="${BATS_TEST_TMPDIR}/missing" \
    bash "${BACKUP}"
  assert_success
  run cat "${CALL_LOG}"
  assert_line --partial "logger --tag restic-backup -- no ${BATS_TEST_TMPDIR}/missing"
  refute_output --partial "restic "
}

@test "restic-backup refuses an env file root does not own, without leaking its environment" {
  local env_file="${BATS_TEST_TMPDIR}/env" notifier="${BATS_TEST_TMPDIR}/notifier"
  echo 'RESTIC_REPOSITORY=/nowhere' > "${env_file}"
  chmod 600 "${env_file}"
  # Logs whether a variable of the caller reached it: env -i drops them all,
  # repository secrets included.
  cat > "${notifier}" << EOF
#!/bin/sh
echo "notify canary=\${LEAK_CANARY:-gone} \$*" >> '${CALL_LOG}'
EOF
  chmod +x "${notifier}"

  run env PATH="${FAKE_BIN}:/usr/bin:/bin" RESTIC_ENV_FILE="${env_file}" \
    NOTIFY_DESKTOP="${notifier}" LEAK_CANARY=present bash "${BACKUP}"
  assert_failure
  run cat "${CALL_LOG}"
  assert_line --partial "notify canary=gone critical Backup failed ${env_file} must be owned by root"
  refute_output --partial "restic "
}
