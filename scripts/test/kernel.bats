setup() {
  load test_helper
  setup_dotfiles_test_env
  # Run the tree's commands as they are, never through sudo.
  export DYBATPHO_PRIVILEGE="false"
  . "${DOTFILES_DIR}/scripts/lib/kernel.sh"
}

function _fake_sudo {
  export DYBATPHO_PRIVILEGE="true" DYBATPHO_PRIVILEGE_COMMAND="fake-sudo"
  cat > "${HOME}/.local/bin/fake-sudo" << EOF
#!/usr/bin/env bash
printf 'elevated %s\n' "\$*" >> "${BATS_TEST_TMPDIR}/calls"
EOF
  chmod +x "${HOME}/.local/bin/fake-sudo"
}

@test "kernel::run_in_tree runs as the user in a tree the user can write" {
  _fake_sudo
  local tree="${BATS_TEST_TMPDIR}/linux"
  dybatpho::ensure_dir "${tree}" > /dev/null

  run kernel::run_in_tree "${tree}" -- touch "${tree}/.config"
  assert_success
  assert [ -f "${tree}/.config" ]
  assert [ ! -e "${BATS_TEST_TMPDIR}/calls" ]
}

@test "kernel::run_in_tree elevates in a tree the user cannot write" {
  _fake_sudo
  local tree="${BATS_TEST_TMPDIR}/linux"
  dybatpho::ensure_dir "${tree}" > /dev/null
  chmod a-w "${tree}"

  run kernel::run_in_tree "${tree}" -- make olddefconfig
  chmod u+w "${tree}"
  assert_success
  run cat "${BATS_TEST_TMPDIR}/calls"
  assert_output 'elevated make olddefconfig'
}

@test "kernel::config_value prints the value of a set option" {
  printf 'CONFIG_HZ=1000\nCONFIG_LSM="selinux,bpf"\n' > "${BATS_TEST_TMPDIR}/.config"

  run kernel::config_value "${BATS_TEST_TMPDIR}/.config" HZ
  assert_success
  assert_output '1000'
  run kernel::config_value "${BATS_TEST_TMPDIR}/.config" LSM
  assert_output '"selinux,bpf"'
}

@test "kernel::config_value prints n for an unset or absent option" {
  printf '# CONFIG_UBSAN is not set\nCONFIG_HZ_1000=y\n' > "${BATS_TEST_TMPDIR}/.config"

  run kernel::config_value "${BATS_TEST_TMPDIR}/.config" UBSAN
  assert_output 'n'
  # A prefix of a set option is a different option.
  run kernel::config_value "${BATS_TEST_TMPDIR}/.config" HZ
  assert_output 'n'
}

@test "kernel::verify_config accepts a config honouring the fragment" {
  cat > "${BATS_TEST_TMPDIR}/.config" << 'EOF'
CONFIG_HZ=1000
CONFIG_PREEMPT=y
CONFIG_DRM_KMS_HELPER=y
CONFIG_LSM="landlock,selinux"
# CONFIG_UBSAN is not set
EOF
  cat > "${BATS_TEST_TMPDIR}/fragment" << 'EOF'
# a comment, and a blank line, are skipped

CONFIG_HZ=1000
CONFIG_PREEMPT=y
CONFIG_DRM_KMS_HELPER=m
CONFIG_LSM="landlock,selinux"
# CONFIG_UBSAN is not set
# CONFIG_ABSENT is not set
EOF

  run kernel::verify_config "${BATS_TEST_TMPDIR}/.config" "${BATS_TEST_TMPDIR}/fragment"
  assert_success
  assert_output ''
}

@test "kernel::verify_config reports every option Kconfig dropped or changed" {
  cat > "${BATS_TEST_TMPDIR}/.config" << 'EOF'
CONFIG_HZ=300
CONFIG_NOUVEAU=m
CONFIG_CPU_SUP_INTEL=y
EOF
  cat > "${BATS_TEST_TMPDIR}/fragment" << 'EOF'
CONFIG_HZ=1000
CONFIG_NOUVEAU=y
# CONFIG_CPU_SUP_INTEL is not set
CONFIG_HIBERNATION=y
EOF

  run kernel::verify_config "${BATS_TEST_TMPDIR}/.config" "${BATS_TEST_TMPDIR}/fragment"
  assert_failure
  assert_line 'HZ: want 1000, got 300'
  # Built-in is required here, a module is not enough.
  assert_line 'NOUVEAU: want y, got m'
  assert_line 'CPU_SUP_INTEL: want n, got y'
  assert_line 'HIBERNATION: want y, got n'
}

@test "kernel::merge_config writes .config from the base, the fragments and olddefconfig" {
  local tree="${BATS_TEST_TMPDIR}/linux" log="${BATS_TEST_TMPDIR}/calls"
  dybatpho::ensure_dir "${tree}/scripts/kconfig" > /dev/null
  cat > "${tree}/scripts/kconfig/merge_config.sh" << EOF
#!/usr/bin/env bash
printf 'merge %s in %s\n' "\$*" "\$(basename "\$PWD")" >> "${log}"
EOF
  cat > "${HOME}/.local/bin/make" << EOF
#!/usr/bin/env bash
printf 'make %s\n' "\$*" >> "${log}"
EOF
  chmod +x "${tree}/scripts/kconfig/merge_config.sh" "${HOME}/.local/bin/make"
  printf 'CONFIG_HZ_300=y\n' > "${BATS_TEST_TMPDIR}/base.config"
  printf 'CONFIG_HZ_1000=y\n' > "${BATS_TEST_TMPDIR}/tuning.config"

  run kernel::merge_config "${tree}" "${BATS_TEST_TMPDIR}/base.config" "${BATS_TEST_TMPDIR}/tuning.config"
  assert_success
  run cat "${tree}/.config"
  assert_output 'CONFIG_HZ_300=y'
  run cat "${log}"
  assert_output "merge -m .config ${BATS_TEST_TMPDIR}/tuning.config in linux
make -C ${tree} olddefconfig"
}

@test "kernel::merge_config refuses a directory that is not a kernel tree" {
  printf 'CONFIG_HZ_300=y\n' > "${BATS_TEST_TMPDIR}/base.config"

  run kernel::merge_config "${BATS_TEST_TMPDIR}" "${BATS_TEST_TMPDIR}/base.config"
  assert_failure
  assert_output --partial "is not a kernel source tree"
}

@test "kernel::merge_config refuses a missing fragment before touching the tree" {
  local tree="${BATS_TEST_TMPDIR}/linux"
  dybatpho::ensure_dir "${tree}/scripts/kconfig" > /dev/null
  touch "${tree}/scripts/kconfig/merge_config.sh"
  printf 'CONFIG_HZ_300=y\n' > "${BATS_TEST_TMPDIR}/base.config"

  run kernel::merge_config "${tree}" "${BATS_TEST_TMPDIR}/base.config" "${BATS_TEST_TMPDIR}/absent"
  assert_failure
  assert_output --partial "Fragment not found"
  assert [ ! -e "${tree}/.config" ]
}

@test "kernel.sh shows its options" {
  run "${DOTFILES_DIR}/scripts/kernel.sh" --help
  assert_success
  assert_output --partial "--configure-only"
  assert_output --partial "--save-base"
}
