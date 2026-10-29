#!/usr/bin/env bats
# dyshellint disable=SC2154 DOTFILES_DIR, HOME and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/network.sh"
  CONFIG="${BATS_TEST_TMPDIR}/config.json"
  STATE="${BATS_TEST_TMPDIR}/state"
  cat > "${CONFIG}" << 'EOF'
{
  "preferGitSSH": true,
  "httpProxy": "http://proxy.example:3128",
  "noProxyAddresses": ["localhost", "10.0.0.0/8"],
  "mirrors": [
    {"gitlab": "dynamo-config/dotfiles", "github": "dynamotn/dotfiles"},
    {"gitlab": "dynamo-config/dotfiles-secrets", "github": "dynamotn/dotfiles-secrets"}
  ]
}
EOF
  # The network the tests pretend to be on: every probe reads these.
  UP_PORTS="${BATS_TEST_TMPDIR}/up-ports"
  : > "${UP_PORTS}"
  # `ssh -G` prints the config; any other call is a handshake, which times out
  # unless port 22 of the host is in UP_PORTS, and otherwise gets as far as
  # authentication unless the host is listed in RESET_HOSTS.
  RESET_HOSTS="${BATS_TEST_TMPDIR}/reset-hosts"
  : > "${RESET_HOSTS}"
  cat > "${HOME}/.local/bin/ssh" << EOF
#!/usr/bin/env bash
if [[ "\${1}" == -G ]]; then
  printf 'hostname %s\nport 22\n' "\${2}"
  exit 0
fi
target="\${*: -1}"
if ! grep -qxF "\${target#git@}:22" "${UP_PORTS}"; then
  echo "ssh: connect to host \${target#git@} port 22: Operation timed out" >&2
elif grep -qxF "\${target}" "${RESET_HOSTS}"; then
  echo "Connection reset by 192.0.2.1 port 22" >&2
else
  echo "git@example: Permission denied (publickey)." >&2
fi
exit 255
EOF
  cat > "${HOME}/.local/bin/curl" << EOF
#!/usr/bin/env bash
grep -qxF "gitlab.com:443" "${UP_PORTS}"
EOF
  chmod +x "${HOME}/.local/bin/ssh" "${HOME}/.local/bin/curl"
  # A port is open when it is listed in UP_PORTS. Defined after test_helper,
  # which loads the real one.
  # dyshellint disable=SC2329 called by network.sh, in place of dybatpho's
  function dybatpho::port_open {
    grep -qxF "${1}:${2}" "${UP_PORTS}"
  }
}

# Print the URL git fetches for a remote URL, with only the given config.
function _git_url {
  # dyshellint disable=BSG062 test_helper, loaded in setup, unsets GIT_DIR and its kin
  GIT_CONFIG_GLOBAL="${1}" GIT_CONFIG_NOSYSTEM=1 git ls-remote --get-url "${2}"
}

@test "network::ssh_up needs a handshake, not only an open port" {
  printf 'gitlab.com:22\n' >> "${UP_PORTS}"
  run network::ssh_up gitlab.com
  assert_success
  # The port answers and the banner comes, then the key exchange is reset.
  printf 'git@gitlab.com\n' >> "${RESET_HOSTS}"
  run network::ssh_up gitlab.com
  assert_failure
  run network::ssh_up github.com
  assert_failure
}

@test "network::ssh_up does not depend on a /dev/tcp port probe" {
  # Such a probe gets killed on macOS for some hosts while SSH to them works.
  printf 'github.com:22\n' >> "${UP_PORTS}"
  function dybatpho::port_open { return 137; }
  run network::ssh_up github.com
  assert_success
}

@test "network::proxy_up probes the host and port of the proxy URL" {
  echo "proxy.example:3128" > "${UP_PORTS}"
  run network::proxy_up "http://proxy.example:3128/"
  assert_success
  run network::proxy_up "http://other.example:3128"
  assert_failure
}

@test "network::proxy_up falls back to the default port of the scheme" {
  echo "proxy.example:80" > "${UP_PORTS}"
  run network::proxy_up "http://proxy.example"
  assert_success
}

@test "network::git_config sends every URL of a mirror to GitLab over SSH" {
  network::git_config true true true "${CONFIG}" > "${BATS_TEST_TMPDIR}/git.config"
  local url
  for url in https://github.com/dynamotn/dotfiles.git git@github.com:dynamotn/dotfiles.git \
    https://gitlab.com/dynamo-config/dotfiles.git git@gitlab.com:dynamo-config/dotfiles.git; do
    run _git_url "${BATS_TEST_TMPDIR}/git.config" "${url}"
    assert_output "git@gitlab.com:dynamo-config/dotfiles.git"
  done
}

@test "network::git_config sends a mirror to GitHub over HTTPS when GitLab is down" {
  network::git_config false false false "${CONFIG}" > "${BATS_TEST_TMPDIR}/git.config"
  run _git_url "${BATS_TEST_TMPDIR}/git.config" git@gitlab.com:dynamo-config/dotfiles-secrets.git
  assert_output "https://github.com/dynamotn/dotfiles-secrets.git"
  # The longest rule wins, so dotfiles does not swallow dotfiles-secrets.
  run _git_url "${BATS_TEST_TMPDIR}/git.config" git@gitlab.com:dynamo-config/dotfiles
  assert_output "https://github.com/dynamotn/dotfiles"
}

@test "network::git_config rewrites other repositories by host" {
  network::git_config true false false "${CONFIG}" > "${BATS_TEST_TMPDIR}/git.config"
  run _git_url "${BATS_TEST_TMPDIR}/git.config" https://github.com/someone/tool.git
  assert_output "git@github.com:someone/tool.git"
  run _git_url "${BATS_TEST_TMPDIR}/git.config" git@gitlab.com:someone/tool.git
  assert_output "https://gitlab.com/someone/tool.git"
}

@test "network::proxy_fish erases the proxy when there is none" {
  run network::proxy_fish "" ""
  assert_success
  assert_output "set -e http_proxy https_proxy no_proxy"
}

@test "network::proxy_fish quotes the proxy for fish" {
  command -v fish &> /dev/null || skip "fish not found"
  network::proxy_fish "http://proxy:3128/it's\\x" "localhost" > "${BATS_TEST_TMPDIR}/proxy.fish"
  # shellcheck disable=SC2016 # expanded by fish
  run fish --no-config -c 'source $argv[1]; printf "%s|%s\n" $https_proxy $no_proxy' \
    "${BATS_TEST_TMPDIR}/proxy.fish"
  assert_success
  assert_output "http://proxy:3128/it's\\x|localhost"
}

@test "network::detect uses the proxy and SSH the network allows" {
  printf '%s\n' "proxy.example:3128" "github.com:22" "gitlab.com:443" > "${UP_PORTS}"
  network::detect "${CONFIG}" "${STATE}"
  [[ "${https_proxy}" == "http://proxy.example:3128" ]]
  [[ "${no_proxy}" == "localhost,10.0.0.0/8" ]]
  run _git_url "${STATE}/git.config" https://github.com/dynamotn/dotfiles.git
  assert_output "https://gitlab.com/dynamo-config/dotfiles.git"
  run grep -c "set -gx" "${STATE}/proxy.fish"
  assert_output "3"
  run stat -c '%a' "${STATE}/proxy.fish"
  assert_output "600"
}

@test "network::detect drops an inherited proxy on a network that cannot reach it" {
  export http_proxy="http://stale:1" https_proxy="http://stale:1"
  network::detect "${CONFIG}" "${STATE}"
  [[ -z "${https_proxy-}" ]]
  run cat "${STATE}/proxy.fish"
  assert_output "set -e http_proxy https_proxy no_proxy"
  run _git_url "${STATE}/git.config" git@gitlab.com:dynamo-config/dotfiles.git
  assert_output "https://github.com/dynamotn/dotfiles.git"
}

@test "network::detect keeps HTTPS when the machine does not prefer SSH" {
  printf '%s\n' "github.com:22" "gitlab.com:22" "gitlab.com:443" > "${UP_PORTS}"
  dybatpho::json_query "${CONFIG}" '.preferGitSSH = false' > "${CONFIG}.new"
  mv "${CONFIG}.new" "${CONFIG}"
  network::detect "${CONFIG}" "${STATE}"
  run _git_url "${STATE}/git.config" git@github.com:someone/tool.git
  assert_output "https://github.com/someone/tool.git"
}
