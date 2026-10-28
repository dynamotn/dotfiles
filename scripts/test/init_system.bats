# dyshellint disable=SC2154 DOTFILES_DIR and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/init_system.sh"
}

@test "init_system::enable_systemd_service enables user services when systemd is running" {
  local args_file="${BATS_TEST_TMPDIR}/systemctl-args"
  cat > "${HOME}/.local/bin/systemctl" << EOF
#!/usr/bin/env bash
if [[ "\$1" == "is-system-running" ]]; then
  exit 0
fi
echo "\$*" > "${args_file}"
EOF
  chmod +x "${HOME}/.local/bin/systemctl"

  run init_system::enable_systemd_service sample.service true
  assert_success
  run cat "${args_file}"
  assert_success
  assert_output 'enable --now --user sample.service'
}

@test "init_system::enable_openrc_service enables user services without sudo" {
  local args_file="${BATS_TEST_TMPDIR}/rc-update-args"
  cat > "${HOME}/.local/bin/rc-service" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "${HOME}/.local/bin/rc-update" << EOF
#!/usr/bin/env bash
echo "\$*" > "${args_file}"
EOF
  chmod +x "${HOME}/.local/bin/rc-service" "${HOME}/.local/bin/rc-update"

  run init_system::enable_openrc_service sample true
  assert_success
  run cat "${args_file}"
  assert_success
  assert_output '--user add sample'
}

@test "init_system::enable_termux_service enables and starts the service" {
  local actions_file="${BATS_TEST_TMPDIR}/termux-actions"
  cat > "${HOME}/.local/bin/sv-enable" << EOF
#!/usr/bin/env bash
printf 'enable:%s\n' "\$*" >> "${actions_file}"
EOF
  cat > "${HOME}/.local/bin/sv" << EOF
#!/usr/bin/env bash
printf 'sv:%s\n' "\$*" >> "${actions_file}"
EOF
  chmod +x "${HOME}/.local/bin/sv-enable" "${HOME}/.local/bin/sv"

  run init_system::enable_termux_service sample
  assert_success
  run cat "${actions_file}"
  assert_success
  assert_output $'enable:sample\nsv:up sample'
}

@test "init_system::enable_launchd_service uses brew services for system services" {
  local args_file="${BATS_TEST_TMPDIR}/brew-args"
  cat > "${HOME}/.local/bin/launchctl" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "${HOME}/.local/bin/brew" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${args_file}"
EOF
  chmod +x "${HOME}/.local/bin/launchctl" "${HOME}/.local/bin/brew"

  PATH="${HOME}/.local/bin:/usr/bin:/bin"
  run init_system::enable_launchd_service SampleApp false
  assert_success
  run cat "${args_file}"
  assert_success
  assert_output 'services start SampleApp'
}

@test "init_system::enable_systemd_user_units reloads, then enables the units" {
  local args_file="${BATS_TEST_TMPDIR}/systemctl-args"
  cat > "${HOME}/.local/bin/systemctl" << EOF
#!/usr/bin/env bash
if [[ "\$2" == "show-environment" ]]; then
  exit 0
fi
echo "\$*" >> "${args_file}"
EOF
  chmod +x "${HOME}/.local/bin/systemctl"

  run init_system::enable_systemd_user_units a.timer b.timer
  assert_success
  run cat "${args_file}"
  assert_success
  assert_output $'--user daemon-reload\n--user enable --now a.timer b.timer'
}

@test "init_system::enable_systemd_user_units skips without a user manager" {
  local args_file="${BATS_TEST_TMPDIR}/systemctl-args"
  cat > "${HOME}/.local/bin/systemctl" << EOF
#!/usr/bin/env bash
if [[ "\$2" == "show-environment" ]]; then
  exit 1
fi
echo "\$*" >> "${args_file}"
EOF
  chmod +x "${HOME}/.local/bin/systemctl"

  run init_system::enable_systemd_user_units a.timer
  assert_success
  assert_output --partial "not running"
  assert_file_not_exists "${args_file}"
}

@test "init_system::bootstrap_launchd_agent reloads the agent in the gui domain" {
  local args_file="${BATS_TEST_TMPDIR}/launchctl-args"
  cat > "${HOME}/.local/bin/launchctl" << EOF
#!/usr/bin/env bash
echo "\$*" >> "${args_file}"
# Not loaded yet: bootout fails as on a first apply
[[ "\$1" != "bootout" ]]
EOF
  chmod +x "${HOME}/.local/bin/launchctl"

  local uid
  uid="$(id -u)"

  run init_system::bootstrap_launchd_agent /tmp/com.sample.plist
  assert_success
  run cat "${args_file}"
  assert_success
  assert_output "bootout gui/${uid} /tmp/com.sample.plist
bootstrap gui/${uid} /tmp/com.sample.plist"
}
