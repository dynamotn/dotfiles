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
  cp -R "${DOTFILES_DIR}/home/.chezmoitemplates/dybw" "${DOTFILES_DIR}/home/.chezmoitemplates/pinentry" \
    "${SANDBOX}/home/.chezmoitemplates/"
  mkdir -p "${SANDBOX}/home/.chezmoitemplates/dytoy"
  cp "${DOTFILES_DIR}/home/.chezmoitemplates/dytoy/pinentry.yaml.tmpl" "${SANDBOX}/home/.chezmoitemplates/dytoy/"
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

# Renders the config file, as on Linux unless an OS is given.
# @arg $1 string chezmoi.os, default linux
function render_config {
  run --separate-stderr chezmoi execute-template --config "${CONFIG}" --source "${SANDBOX}/home" \
    --override-data "{\"chezmoi\":{\"os\":\"${1:-linux}\"}}" \
    --file "${SANDBOX}/home/private_dot_config/dybw/private_config.toml.tmpl"
}

# Prints the packages the pinentry manifest installs from one section.
# @arg $1 string chezmoi.os
# @arg $2 string Section of the manifest, such as macos or ubuntu
function manifest_packages {
  local os section manifest
  dybatpho::expect_args os section -- "$@"
  manifest="$(chezmoi execute-template --config "${CONFIG}" --source "${SANDBOX}/home" \
    --override-data "{\"chezmoi\":{\"os\":\"${os}\"}}" \
    '{{ includeTemplate "dytoy/pinentry.yaml.tmpl" . }}')"
  yq -r ".${section}.packages[].name" <<< "${manifest}"
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
  assert_line 'pinentry = "pinentry-gnome3"'
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

@test "dybw config refuses an identity_url that is not the Bitwarden cloud's" {
  write_account personal << 'EOF'
email: me@example.org
base_url: https://vault.bitwarden.com
identity_url: https://identity.elsewhere.example
lock_timeout: 60
EOF
  write_config true '[]' W
  render_config
  assert_failure
  assert_stderr --partial "dybw profile default: identity_url in personal/rbw.yaml"
  refute_stderr --partial "identity.elsewhere.example"
}

@test "dybw config takes the Bitwarden cloud's identity server" {
  write_account personal << 'EOF'
email: me@example.org
base_url: https://vault.bitwarden.eu
identity_url: https://identity.bitwarden.eu
lock_timeout: 60
EOF
  write_config true '[]' W
  render_config
  assert_success
  assert_line '    server_url = "https://vault.bitwarden.eu"'
}

# Checks the config names the program the pinentry manifest installs.
# @arg $1 string chezmoi.os
# @arg $2 string guiServer
# @arg $3 string Program the config must name
# @arg $4 string Manifest section that installs it
# @arg $5 string Package of that section that ships it
function assert_pinentry {
  local os gui program section package
  dybatpho::expect_args os gui program section package -- "$@"
  write_account personal <<< $'email: e@example.org\nbase_url: https://v.example.org\nlock_timeout: 60'
  write_config true '[]' "${gui}"
  render_config "${os}"
  assert_success
  assert_line "pinentry = \"${program}\""
  run manifest_packages "${os}" "${section}"
  assert_success
  assert_output "${package}"
}

@test "dybw config names pinentry-mac on macOS, as dytoy installs it" {
  assert_pinentry darwin M pinentry-mac macos pinentry-mac
}

@test "dybw config names pinentry-gnome3 on a Linux desktop, as dytoy installs it" {
  assert_pinentry linux W pinentry-gnome3 ubuntu pinentry-gnome3
  assert_pinentry linux X pinentry-gnome3 alpine pinentry-gnome
}

@test "dybw config names pinentry-curses on a headless Linux, as dytoy installs it" {
  assert_pinentry linux 0 pinentry-curses ubuntu pinentry-curses
}
