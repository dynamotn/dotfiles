setup() {
  load test_helper
  SCHEMA_DIR="${DOTFILES_DIR}/schemas"
  DATA_DIR="${DOTFILES_DIR}/home/.chezmoidata"
}

function _require_ys {
  command -v ys &> /dev/null || skip "ys not found – install with: cargo install yaml-schema"
}

@test "home/.chezmoidata/machines.yaml conforms to schema" {
  _require_ys
  run ys -f "${SCHEMA_DIR}/machines.schema.yaml" "${DATA_DIR}/machines.yaml"
  assert_success
}

@test "home/.chezmoidata/choices.yaml conforms to schema" {
  _require_ys
  run ys -f "${SCHEMA_DIR}/choices.schema.yaml" "${DATA_DIR}/choices.yaml"
  assert_success
}

@test "machines schema rejects the secrets of a machine" {
  _require_ys
  local field file="${BATS_TEST_TMPDIR}/machines.yaml"
  for field in "httpProxy: http://proxy:3128" "noProxyAddresses: []" "customHostname: h"; do
    printf 'machines:\n  test0:\n    %s\n' "${field}" > "${file}"
    run ys -f "${SCHEMA_DIR}/machines.schema.yaml" "${file}"
    assert_failure
  done
}

@test "choices schema rejects a choice without options" {
  _require_ys
  local file="${BATS_TEST_TMPDIR}/choices.yaml"
  yq '.choices.place = {"default": "home"}' "${DATA_DIR}/choices.yaml" > "${file}"
  run ys -f "${SCHEMA_DIR}/choices.schema.yaml" "${file}"
  assert_failure
}
