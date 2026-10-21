setup() {
  load test_helper
  SCHEMA_FILE="${DOTFILES_DIR}/schemas/machines.schema.yaml"
  MACHINES_FILE="${DOTFILES_DIR}/home/.chezmoidata/machines.yaml"
}

function _require_ys {
  command -v ys &> /dev/null || skip "ys not found – install with: cargo install yaml-schema"
}

@test "home/.chezmoidata/machines.yaml conforms to schema" {
  _require_ys
  run ys -f "${SCHEMA_FILE}" "${MACHINES_FILE}"
  assert_success
}

@test "machines schema rejects the secrets of a machine" {
  _require_ys
  local file
  for field in "httpProxy: http://proxy:3128" "noProxyAddresses: []" "customHostname: h"; do
    file="${BATS_TEST_TMPDIR}/machines.yaml"
    printf 'machines:\n  test0:\n    %s\n' "${field}" > "${file}"
    run ys -f "${SCHEMA_FILE}" "${file}"
    assert_failure
  done
}

@test "machines schema rejects an answer the config template would not offer" {
  _require_ys
  local file="${BATS_TEST_TMPDIR}/machines.yaml"
  printf 'machines:\n  test0:\n    kind: toaster\n' > "${file}"
  run ys -f "${SCHEMA_FILE}" "${file}"
  assert_failure
}
