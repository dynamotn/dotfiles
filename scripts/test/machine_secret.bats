setup() {
  load test_helper
  setup_dotfiles_test_env
  command -v chezmoi &> /dev/null || skip "chezmoi not found"
  command -v age &> /dev/null || skip "age not found"
  command -v age-keygen &> /dev/null || skip "age-keygen not found"
  # A sandbox source with the partial and a secrets tree of its own, encrypted
  # to a throwaway key: the real secrets are never read here.
  SANDBOX="${BATS_TEST_TMPDIR}/dotfiles"
  mkdir -p "${SANDBOX}/home/.chezmoitemplates/machine"
  cp "${DOTFILES_DIR}/home/.chezmoitemplates/machine/secret.tmpl" \
    "${SANDBOX}/home/.chezmoitemplates/machine/"
  KEY="${BATS_TEST_TMPDIR}/test.key"
  age-keygen -o "${KEY}" 2> /dev/null
  RECIPIENT="$(age-keygen -y "${KEY}")"
  CONFIG="${BATS_TEST_TMPDIR}/chezmoi.yaml"
}

# Encrypts stdin as the machine secrets of an identity.
# @arg $1 string Identity, such as personal or enterprise-T1
function write_machine_secret {
  local identity
  dybatpho::expect_args identity -- "$@"
  mkdir -p "${SANDBOX}/secrets/data/${identity}"
  age -r "${RECIPIENT}" -o "${SANDBOX}/secrets/data/${identity}/machine.yaml.age"
}

# Writes the chezmoi config of a machine.
# @arg $1 string Machine code
# @arg $2 string Owner company, empty for none
# @arg $3 string decryptPersonal, true or false
# @arg $4 string decryptEnterprise, as a YAML list
function write_config {
  local code company personal enterprise
  dybatpho::expect_args code company personal enterprise -- "$@"
  cat > "${CONFIG}" << EOF
sourceDir: "${SANDBOX}/home"
encryption: age
age:
  identity: "${KEY}"
  recipient: "${RECIPIENT}"
data:
  code: "${code}"
  company: "${company}"
  decryptPersonal: ${personal}
  decryptEnterprise: ${enterprise}
EOF
}

function render_secret {
  run --separate-stderr chezmoi execute-template --config "${CONFIG}" --source "${SANDBOX}/home" \
    '{{ includeTemplate "machine/secret.tmpl" . }}'
}

@test "machine/secret.tmpl reads the owner company's secrets of the machine" {
  write_machine_secret enterprise-T1 << 'EOF'
machines:
  test0:
    httpProxy: "http://proxy:3128"
    noProxyAddresses: [localhost, 10.0.0.0/8]
    customHostname: "test0.example"
EOF
  write_machine_secret personal << 'EOF'
machines:
  test0:
    httpProxy: "http://personal:3128"
EOF
  write_config test0 T1 true '[T1]'
  render_secret
  assert_success
  local expected='{"customHostname":"test0.example","httpProxy":"http://proxy:3128",'
  expected+='"noProxyAddresses":["localhost","10.0.0.0/8"]}'
  assert_output "${expected}"
}

@test "machine/secret.tmpl falls back to the personal secrets" {
  write_machine_secret personal << 'EOF'
machines:
  test0:
    customHostname: "home0"
EOF
  # T1 owns the machine, but it does not decrypt T1.
  write_config test0 T1 true '[]'
  render_secret
  assert_success
  assert_output '{"customHostname":"home0","httpProxy":"","noProxyAddresses":[]}'
}

@test "machine/secret.tmpl is empty for a machine missing from the secrets" {
  write_machine_secret personal << 'EOF'
machines:
  other:
    httpProxy: "http://other:3128"
EOF
  write_config test0 "" true '[]'
  render_secret
  assert_success
  assert_output '{"customHostname":"","httpProxy":"","noProxyAddresses":[]}'
}

@test "machine/secret.tmpl decrypts nothing when the machine decrypts no identity" {
  # Not age at all: decrypting it would fail the render.
  mkdir -p "${SANDBOX}/secrets/data/personal"
  printf 'not encrypted\n' > "${SANDBOX}/secrets/data/personal/machine.yaml.age"
  write_config test0 "" false '[]'
  render_secret
  assert_success
  assert_output '{"customHostname":"","httpProxy":"","noProxyAddresses":[]}'
}
