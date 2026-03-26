setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/init_system.sh"
}

@test "init::enable_systemd_service enables user services when systemd is running" {
  local args_file="${BATS_TEST_TMPDIR}/systemctl-args"
  cat > "${HOME}/.local/bin/systemctl" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "is-system-running" ]]; then
  exit 0
fi
echo "\$*" > "${args_file}"
EOF
  chmod +x "${HOME}/.local/bin/systemctl"

  run init::enable_systemd_service sample.service true
  assert_success
  run cat "${args_file}"
  assert_success
  assert_output 'enable --now --user sample.service'
}

@test "init::enable_openrc_service enables user services without sudo" {
  local args_file="${BATS_TEST_TMPDIR}/rc-update-args"
  cat > "${HOME}/.local/bin/rc-service" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "${HOME}/.local/bin/rc-update" <<EOF
#!/usr/bin/env bash
echo "\$*" > "${args_file}"
EOF
  chmod +x "${HOME}/.local/bin/rc-service" "${HOME}/.local/bin/rc-update"

  run init::enable_openrc_service sample true
  assert_success
  run cat "${args_file}"
  assert_success
  assert_output '--user add sample'
}

@test "init::enable_termux_service enables and starts the service" {
  local actions_file="${BATS_TEST_TMPDIR}/termux-actions"
  cat > "${HOME}/.local/bin/sv-enable" <<EOF
#!/usr/bin/env bash
printf 'enable:%s\n' "\$*" >> "${actions_file}"
EOF
  cat > "${HOME}/.local/bin/sv" <<EOF
#!/usr/bin/env bash
printf 'sv:%s\n' "\$*" >> "${actions_file}"
EOF
  chmod +x "${HOME}/.local/bin/sv-enable" "${HOME}/.local/bin/sv"

  run init::enable_termux_service sample
  assert_success
  run cat "${actions_file}"
  assert_success
  assert_output $'enable:sample\nsv:up sample'
}

@test "init::enable_launchd_service bootstraps system daemon via launchctl" {
  local plist_dir="${BATS_TEST_TMPDIR}/zerobrew/opt/SampleApp"
  mkdir -p "$plist_dir"
  cat > "${plist_dir}/homebrew.mxcl.SampleApp.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>homebrew.mxcl.SampleApp</string></dict></plist>
EOF
  ZEROBREW_ROOT="${BATS_TEST_TMPDIR}/zerobrew"

  local actions_file="${BATS_TEST_TMPDIR}/launchctl-args"
  cat > "${HOME}/.local/bin/launchctl" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "list" ]]; then exit 1; fi
printf '%s\n' "\$*" >> "${actions_file}"
EOF
  chmod +x "${HOME}/.local/bin/launchctl"

  export DRY_RUN='true'
  PATH="${HOME}/.local/bin:/usr/bin:/bin"
  run init::enable_launchd_service SampleApp false
  assert_success
  assert_output --partial 'launchctl bootstrap system'
  assert_output --partial 'homebrew.mxcl.SampleApp.plist'
}
