# dyshellint disable=SC2154 DOTFILES_DIR and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  command -v chezmoi &> /dev/null || skip "chezmoi not found"
  command -v age &> /dev/null || skip "age not found"
  command -v age-keygen &> /dev/null || skip "age-keygen not found"
  # A sandbox source with the partial, the two targets and a secrets tree of
  # its own, encrypted to a throwaway key: the real secrets are never read here.
  SANDBOX="${BATS_TEST_TMPDIR}/dotfiles"
  mkdir -p "${SANDBOX}/home/.chezmoitemplates/dyai" "${SANDBOX}/home/private_dot_config/dyai"
  cp "${DOTFILES_DIR}/home/.chezmoitemplates/dyai/node-key.tmpl" \
    "${DOTFILES_DIR}/home/.chezmoitemplates/dyai/node-identity.tmpl" "${SANDBOX}/home/.chezmoitemplates/dyai/"
  cp -R "${DOTFILES_DIR}/home/private_dot_config/dyai/private_node" "${SANDBOX}/home/private_dot_config/dyai/"
  KEY="${BATS_TEST_TMPDIR}/test.key"
  age-keygen -o "${KEY}" 2> /dev/null
  RECIPIENT="$(age-keygen -y "${KEY}")"
  CONFIG="${BATS_TEST_TMPDIR}/chezmoi.yaml"
  # Stand-ins: the templates pass the text through, whatever it is.
  PRIVATE=$'fake signing key\nAAAA\nend'
}

# Encrypts stdin as the dyai secrets of an identity, personal by default.
function write_dyai_secret {
  local identity="${1:-personal}"
  mkdir -p "${SANDBOX}/secrets/data/${identity}"
  age -r "${RECIPIENT}" -o "${SANDBOX}/secrets/data/${identity}/dyai.yaml.age"
}

# Writes the chezmoi config of a machine.
# @arg $1 string Machine code
# @arg $2 string decryptPersonal, true or false
# @arg $3 string Owner company, empty by default
# @arg $4 string decryptEnterprise, as a YAML list, [] by default
function write_config {
  local code personal
  dybatpho::expect_args code personal -- "$@"
  local company="${3:-}" enterprise="${4:-[]}"
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

# Renders a target of the sandbox source, as chezmoi apply would write it.
# @arg $1 string Source file under home/
function render {
  local file
  dybatpho::expect_args file -- "$@"
  run --separate-stderr chezmoi execute-template --config "${CONFIG}" --source "${SANDBOX}/home" \
    --file "${SANDBOX}/home/${file}"
}

function write_two_nodes {
  {
    printf 'nodes:\n  laptop:\n    signing: |\n'
    printf '      %s\n' "${PRIVATE//$'\n'/$'\n'      }"
    printf '    public: "ssh-ed25519 AAAAlaptop laptop"\n'
    printf '    deploy: |\n      fake deploy key\n      DEPLOY\n'
    printf '      end\n    deploy_public: "ssh-ed25519 AAAAdeploy laptop"\n'
    printf '  pc:\n    signing: |\n      fake signing key\n      PC\n'
    printf '      end\n    public: "ssh-ed25519 AAAApc pc"\n'
  } | write_dyai_secret
}

@test "dyai node key: each machine gets its own key from the shared secrets file" {
  write_two_nodes
  write_config laptop true
  render private_dot_config/dyai/private_node/private_signing.tmpl
  assert_success
  assert_output "${PRIVATE}"
  render private_dot_config/dyai/private_node/signing.pub.tmpl
  assert_output "ssh-ed25519 AAAAlaptop laptop"
  write_config pc true
  render private_dot_config/dyai/private_node/signing.pub.tmpl
  assert_output "ssh-ed25519 AAAApc pc"
}

@test "dyai node key: the rendered key ends with a newline, as ssh-keygen needs" {
  write_two_nodes
  write_config laptop true
  chezmoi execute-template --config "${CONFIG}" --source "${SANDBOX}/home" \
    --file "${SANDBOX}/home/private_dot_config/dyai/private_node/private_signing.tmpl" > "${BATS_TEST_TMPDIR}/key"
  local content=""
  IFS= read -r -d '' content < "${BATS_TEST_TMPDIR}/key" || true
  [[ "${content}" == "${PRIVATE}"$'\n' ]]
}

@test "dyai node key: empty for a machine missing from the secrets" {
  write_two_nodes
  write_config other true
  render private_dot_config/dyai/private_node/private_signing.tmpl
  assert_success
  assert_output ""
}

@test "dyai node key: a machine that does not decrypt personal secrets gets none" {
  write_two_nodes
  write_config laptop false
  render private_dot_config/dyai/private_node/private_signing.tmpl
  assert_success
  assert_output ""
  render private_dot_config/dyai/private_node/signing.pub.tmpl
  assert_output ""
}

@test "dyai node key: empty without the secrets file" {
  write_config laptop true
  render private_dot_config/dyai/private_node/private_signing.tmpl
  assert_success
  assert_output ""
}

@test "dyai node key: the deploy pair renders beside the signing one" {
  write_two_nodes
  write_config laptop true
  render private_dot_config/dyai/private_node/private_deploy.tmpl
  assert_success
  assert_output $'fake deploy key\nDEPLOY\nend'
  render private_dot_config/dyai/private_node/deploy.pub.tmpl
  assert_output "ssh-ed25519 AAAAdeploy laptop"
  # A machine from before deploy keys gets none, and keeps its signing key.
  write_config pc true
  render private_dot_config/dyai/private_node/private_deploy.tmpl
  assert_output ""
}

@test "dyai node key: a company machine without the personal secrets reads its company's" {
  printf 'nodes:\n  work:\n    public: "ssh-ed25519 AAAAwork work"\n' | write_dyai_secret enterprise-F1
  write_two_nodes
  write_config work false F1 '[F1]'
  render private_dot_config/dyai/private_node/signing.pub.tmpl
  assert_success
  assert_output "ssh-ed25519 AAAAwork work"
  # Its company's secrets it cannot decrypt: no key.
  write_config work false F1 '[]'
  render private_dot_config/dyai/private_node/signing.pub.tmpl
  assert_output ""
}

@test "dyai node key: a machine with both the personal and its company's secrets uses the personal" {
  printf 'nodes:\n  laptop:\n    public: "ssh-ed25519 AAAAcompany laptop"\n' | write_dyai_secret enterprise-F1
  write_two_nodes
  write_config laptop true F1 '[F1]'
  render private_dot_config/dyai/private_node/signing.pub.tmpl
  assert_output "ssh-ed25519 AAAAlaptop laptop"
}
