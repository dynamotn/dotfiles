# dyshellint disable=SC2154 DOTFILES_DIR and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  command -v chezmoi &> /dev/null || skip "chezmoi not found"
  command -v age &> /dev/null || skip "age not found"
  command -v age-keygen &> /dev/null || skip "age-keygen not found"
  # A sandbox source with the templates and a secrets tree of its own,
  # encrypted to a throwaway key: the real secrets are never read here.
  SANDBOX="${BATS_TEST_TMPDIR}/dotfiles"
  mkdir -p "${SANDBOX}/home/.chezmoitemplates" "${SANDBOX}/home/private_dot_config"
  cp -R "${DOTFILES_DIR}/home/.chezmoitemplates/dybw" "${SANDBOX}/home/.chezmoitemplates/"
  cp -R "${DOTFILES_DIR}/home/private_dot_config/dybw" "${SANDBOX}/home/private_dot_config/"
  KEY="${BATS_TEST_TMPDIR}/test.key"
  age-keygen -o "${KEY}" 2> /dev/null
  RECIPIENT="$(age-keygen -y "${KEY}")"
  CONFIG="${BATS_TEST_TMPDIR}/chezmoi.yaml"
}

# Encrypts stdin as the rbw.yaml of an identity.
# @arg $1 string Identity, such as personal or enterprise-F1
function write_account {
  local identity
  dybatpho::expect_args identity -- "$@"
  mkdir -p "${SANDBOX}/secrets/data/${identity}"
  age -r "${RECIPIENT}" -o "${SANDBOX}/secrets/data/${identity}/rbw.yaml.age"
}

# Writes the chezmoi config of a machine.
# @arg $1 string decryptPersonal, true or false
# @arg $2 string decryptEnterprise, as a YAML list
# @arg $3 string guiServer
function write_config {
  local personal enterprise gui
  dybatpho::expect_args personal enterprise gui -- "$@"
  cat > "${CONFIG}" << EOF
sourceDir: "${SANDBOX}/home"
encryption: age
age:
  identity: "${KEY}"
  recipient: "${RECIPIENT}"
data:
  decryptPersonal: ${personal}
  decryptEnterprise: ${enterprise}
  guiServer: "${gui}"
EOF
}

# Renders the config file as on a Linux machine.
function render_config {
  run --separate-stderr chezmoi execute-template --config "${CONFIG}" --source "${SANDBOX}/home" \
    --override-data '{"chezmoi":{"os":"linux"}}' \
    --file "${SANDBOX}/home/private_dot_config/dybw/private_config.toml.tmpl"
}

@test "dybw config has a profile per rbw account, in minutes rounded up" {
  write_account personal << 'EOF'
email: me@example.org
base_url: https://vault.example.org/
identity_url: null
lock_timeout: 3601
EOF
  write_account enterprise-F1 << 'EOF'
email: me@f1.example
base_url: https://vault.bitwarden.com
identity_url: https://identity.bitwarden.com
lock_timeout: 900
EOF
  write_config true '[F1]' W
  render_config
  assert_success
  assert_line 'default = "default"'
  assert_line 'pinentry = "pinentry-gtk"'
  assert_line '  [profiles.default]'
  assert_line '    server_url = "https://vault.example.org/"'
  assert_line '    lock_timeout_minutes = 61'
  assert_line '  [profiles.enterprise-f1]'
  assert_line '    email = "me@f1.example"'
  assert_line '    lock_timeout_minutes = 15'
}

@test "dybw config defaults to the company profile without the personal one" {
  write_account enterprise-F1 << 'EOF'
email: me@f1.example
base_url: https://vault.f1.example
lock_timeout: 60
EOF
  write_config false '[F1]' 0
  render_config
  assert_success
  assert_line 'default = "enterprise-f1"'
  assert_line 'pinentry = "pinentry-curses"'
  refute_line --partial '[profiles.default]'
}

@test "dybw config is empty and decrypts nothing without an account" {
  # Not age at all: decrypting it would fail the render.
  mkdir -p "${SANDBOX}/secrets/data/personal"
  printf 'not encrypted\n' > "${SANDBOX}/secrets/data/personal/rbw.yaml.age"
  write_config false '[]' W
  render_config
  assert_success
  assert_output ''
}

@test "dybw config refuses an identity_url it cannot derive from base_url" {
  write_account personal << 'EOF'
email: me@example.org
base_url: https://vault.example.org
identity_url: https://login.example.org
lock_timeout: 60
EOF
  write_config true '[]' W
  render_config
  assert_failure
  assert_stderr --partial "dybw profile default: identity_url in personal/rbw.yaml"
  refute_stderr --partial "login.example.org"
}

@test "dybw config takes an identity_url that is base_url/identity" {
  write_account personal << 'EOF'
email: me@example.org
base_url: https://vault.example.org/
identity_url: https://vault.example.org/identity
lock_timeout: 60
EOF
  write_config true '[]' W
  render_config
  assert_success
  assert_line '    lock_timeout_minutes = 1'
}
