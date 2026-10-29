setup() {
  load test_helper
  setup_dotfiles_test_env
  SETUP="${DOTFILES_DIR}/scripts/setup.sh"
  CALL_LOG="${BATS_TEST_TMPDIR}/calls.log"
  : > "${CALL_LOG}"
  # A sandbox stands in for the repository, which a test must never write
  # into. Its config template is reached through home/, as in the repository.
  SANDBOX="${BATS_TEST_TMPDIR}/dotfiles"
  mkdir -p "${SANDBOX}/home/.chezmoidata"
  cp "${DOTFILES_DIR}/.chezmoi.yaml.tmpl" "${DOTFILES_DIR}/.chezmoiroot" \
    "${DOTFILES_DIR}/.chezmoiversion" "${SANDBOX}/"
  cp -P "${DOTFILES_DIR}/home/.chezmoi.yaml.tmpl" "${SANDBOX}/home/"
  # The options of its choice questions are data the config template reads.
  cp "${DOTFILES_DIR}/home/.chezmoidata/choices.yaml" \
    "${DOTFILES_DIR}/home/.chezmoidata/companies.yaml" "${SANDBOX}/home/.chezmoidata/"
  # The suite may itself run on CI or in a container; each test says which.
  unset CI GITHUB_ACTIONS GITLAB_CI container CODESPACES REMOTE_CONTAINERS DEVCONTAINER KUBERNETES_SERVICE_HOST
}

# Runs a snippet with setup.sh sourced, which defines its functions without
# running it, and with the sandbox as the repository root.
# @arg $1 string Bash code to run
function run_setup {
  local snippet
  dybatpho::expect_args snippet -- "$@"
  # stderr apart: it carries the log, and on macOS the warnings of a /bin/sh
  # fake that cannot import the functions dybatpho exports.
  run --separate-stderr "${BASH}" -c '. "$1"; ROOT_DIR="$2"; '"${snippet}" _ "${SETUP}" "${SANDBOX}"
}

# Writes a fake `chezmoi` that reports the given version.
# @arg $1 string Version as `chezmoi --version` prints it
function fake_chezmoi_version {
  local version
  dybatpho::expect_args version -- "$@"
  printf '#!/bin/sh\nprintf "chezmoi version %s, commit test\\n"\n' "${version}" > "${HOME}/.local/bin/chezmoi"
  chmod +x "${HOME}/.local/bin/chezmoi"
}

@test "setup.sh answers the prompts the config template really asks" {
  # The replacements it made on the template text matched nothing any more,
  # so `-i F1` built enterprise images without enterprise data, silently.
  run_setup 'printf "%s\n%s\n" "${PROMPT_PERSONAL}" "${PROMPT_ENTERPRISE}"'
  assert_success
  assert_equal "${#lines[@]}" 2
  local prompt
  while IFS= read -r prompt; do
    grep -qF "\"${prompt}\"" "${DOTFILES_DIR}/.chezmoi.yaml.tmpl"
  done <<< "${output}"
}

@test "setup.sh turns --identities into decryption answers chezmoi applies" {
  dybatpho::is command chezmoi || skip "chezmoi is not installed"

  IDENTITIES="personal, F1,,ZOO," run_setup \
    '_chezmoi_init_args; chezmoi "${CHEZMOI_INIT_ARGS[@]}" < /dev/null'
  assert_success
  local config="${XDG_CONFIG_HOME}/chezmoi/chezmoi.yaml"
  run yq -o=j -I=0 '.data.decryptPersonal' "${config}"
  assert_output "true"
  run yq -o=j -I=0 '.data.decryptEnterprise' "${config}"
  assert_output '["F1","ZOO"]'
  run yq -r '.age.identities[]' "${config}"
  assert_output --partial "enterprise-F1.key"
  assert_output --partial "enterprise-ZOO.key"
}

@test "chezmoi init reads the config template of the repository through home/" {
  dybatpho::is command chezmoi || skip "chezmoi is not installed"
  # A copy in home/ went stale whenever the template changed without a run
  # of setup.sh, and `chezmoi init` then asked the old questions.
  run readlink "${DOTFILES_DIR}/home/.chezmoi.yaml.tmpl"
  assert_output "../.chezmoi.yaml.tmpl"

  run_setup '_chezmoi_init_args; chezmoi "${CHEZMOI_INIT_ARGS[@]}" < /dev/null'
  assert_success
  run yq -r '.sourceDir' "${XDG_CONFIG_HOME}/chezmoi/chezmoi.yaml"
  assert_output "${SANDBOX}"
}

@test "setup.sh takes the defaults when stdin is not a terminal" {
  run_setup '_chezmoi_init_args < /dev/null; printf "%s\n" "${CHEZMOI_INIT_ARGS[@]}"'
  assert_success
  assert_line -- "--promptDefaults"
  assert_line -- "--no-tty"
  refute_line -- "--prompt"
}

@test "setup.sh takes the defaults inside a container or on CI" {
  # Bats gives no terminal, so one is faked to leave the other signals alone.
  local variable
  for variable in container=podman CI=true REMOTE_CONTAINERS=true; do
    run_setup "dybatpho::is_tty() { return 0; }; export ${variable}; _is_unattended"
    assert_success
  done
  if ! dybatpho::is_container; then
    run_setup 'dybatpho::is_tty() { return 0; }; _is_unattended'
    assert_failure
  fi
}

@test "setup.sh prompts when someone can answer" {
  run_setup '_is_unattended() { return 1; }; _chezmoi_init_args; printf "%s\n" "${CHEZMOI_INIT_ARGS[@]}"'
  assert_success
  assert_line -- "--prompt"
  refute_line -- "--promptDefaults"
}

# Writes a machines.yaml into the sandbox, from stdin.
function write_machines_yaml {
  cat > "${SANDBOX}/home/.chezmoidata/machines.yaml"
}

# Renders the config template of the sandbox as `chezmoi init` would, for the
# given machine code, with no terminal to answer any other question.
# @arg $1 string Machine code
function render_config_for {
  local code
  dybatpho::expect_args code -- "$@"
  run --separate-stderr chezmoi execute-template --init --no-tty --source "${SANDBOX}" \
    --promptString "What is this machine's name=${code}" \
    --file "${SANDBOX}/home/.chezmoi.yaml.tmpl" < /dev/null
}

# Skips a test of the default kind where the config template detects a
# container, by the same markers, and so defaults the kind to "container".
function skip_in_container {
  if [[ -n "${container-}" || -e /run/.containerenv || -e /.dockerenv ]]; then
    skip "in a container the kind defaults to container"
  fi
}

@test "the config template takes the answers of a machine from machines.yaml" {
  dybatpho::is command chezmoi || skip "chezmoi is not installed"
  write_machines_yaml << 'EOF'
machines:
  test0:
    place: "office"
    kind: "laptop"
    company: "T1"
    decryptPersonal: false
    decryptEnterprise: [T1]
    guiServer: "W"
    guiDriver: "I"
    guiWinManager: "N"
    languages: [vi]
    browser: "F"
    browserEnterpriseProfiles: [T1]
    mailClient: ""
    mailEnterpriseProfiles: []
    terminalMultiplexer: "T"
    hasSound: true
    hasBluetooth: false
    hasWifi: true
    preferGitSSH: true
    darkMode: false
EOF
  # Without a terminal, a question left would fail the render.
  render_config_for test0
  assert_success
  local config="${output}"
  local query='.data | [.place, .kind, .company, .guiWinManager, .browser, .mailClient,'
  query+=' .terminalMultiplexer, .darkMode, .hasWifi]'
  run yq -o=j -I=0 "${query}" <<< "${config}"
  assert_output '["office","laptop","T1","N","F","","T",false,true]'
  run yq -o=j -I=0 '.data.decryptEnterprise' <<< "${config}"
  assert_output '["T1"]'
  run yq -r '.age.identities[]' <<< "${config}"
  assert_output --partial "enterprise-T1.key"
  # The secrets of a machine never land in the plain config.
  run yq -o=j -I=0 '.data | [has("httpProxy"), has("noProxyAddresses"), has("customHostname")]' <<< "${config}"
  assert_output '[false,false,false]'
}

@test "the config template rejects a stored answer it would not offer" {
  dybatpho::is command chezmoi || skip "chezmoi is not installed"
  write_machines_yaml << 'EOF'
machines:
  test0:
    kind: "toaster"
EOF
  render_config_for test0
  assert_failure
  assert_stderr --partial "machines.yaml: kind=toaster of test0 is not one of"
}

@test "the config template falls back to the questions for an unlisted machine" {
  dybatpho::is command chezmoi || skip "chezmoi is not installed"
  skip_in_container
  write_machines_yaml << 'EOF'
machines:
  test0:
    kind: "laptop"
EOF
  # Without a terminal, every question takes its default.
  render_config_for other
  assert_success
  run yq -o=j -I=0 '.data | [.code, .kind]' <<< "${output}"
  assert_output '["other","pc"]'
}

@test "every machine of machines.yaml gives answers the config template offers" {
  dybatpho::is command chezmoi || skip "chezmoi is not installed"
  cp "${DOTFILES_DIR}/home/.chezmoidata/machines.yaml" "${SANDBOX}/home/.chezmoidata/"
  local code listed
  local -a codes
  listed="$(yq -r '.machines | keys | .[]' "${SANDBOX}/home/.chezmoidata/machines.yaml")"
  mapfile -t codes <<< "${listed}"
  assert [ "${#codes[@]}" -gt 0 ]
  for code in "${codes[@]}"; do
    render_config_for "${code}"
    assert_success
  done
}

@test "the config template offers the options of choices.yaml" {
  dybatpho::is command chezmoi || skip "chezmoi is not installed"
  skip_in_container
  yq -i '.choices.place.options = ["moon", "home"] | .choices.kind.default = "laptop"' \
    "${SANDBOX}/home/.chezmoidata/choices.yaml"
  write_machines_yaml << 'EOF'
machines:
  test0:
    place: "home"
  test1:
    place: "cloud"
EOF
  # Without a terminal, every question left takes its default.
  render_config_for other
  assert_success
  run yq -o=j -I=0 '.data | [.place, .kind]' <<< "${output}"
  assert_output '["moon","laptop"]'
  render_config_for test0
  assert_success
  render_config_for test1
  assert_failure
  assert_stderr --partial "machines.yaml: place=cloud of test1 is not one of moon, home"
}

@test "setup.sh rejects an identity chezmoi cannot be handed" {
  IDENTITIES="F1/T1" run_setup '_chezmoi_init_args < /dev/null'
  assert_failure
  assert_stderr --partial "Invalid identity: F1/T1"
}

@test "setup.sh replaces a chezmoi older than .chezmoiversion" {
  fake_chezmoi_version v2.1.0
  run_setup '_chezmoi_is_recent'
  assert_failure

  fake_chezmoi_version v99.0.0
  run_setup '_chezmoi_is_recent'
  assert_success
}

@test "setup.sh fits git and the proxy to the network before the full apply" {
  # chezmoi applies dynet's config: a proxy on a closed port, so this network
  # cannot reach it. curl, standing for GitLab, answers nothing either.
  cat > "${HOME}/.local/bin/chezmoi" << EOF
#!/bin/sh
printf 'chezmoi %s\n' "\$*" >> "${CALL_LOG}"
mkdir -p "${HOME}/.config/dynet"
printf '{"preferGitSSH":false,"httpProxy":"http://127.0.0.1:9","noProxyAddresses":[]}\n' \
  > "${HOME}/.config/dynet/config.json"
EOF
  printf '#!/bin/sh\nexit 7\n' > "${HOME}/.local/bin/curl"
  chmod +x "${HOME}/.local/bin/chezmoi" "${HOME}/.local/bin/curl"
  # dyshellint disable=SC2016 expanded by the shell run_setup starts
  local snippet='_detect_network; printf "%s|" "${http_proxy-unset}";'
  snippet+=' cat "${HOME}/.local/state/dynet/proxy.fish"'
  http_proxy="http://stale:1" run_setup "${snippet}"
  assert_success
  assert_output "unset|set -e http_proxy https_proxy no_proxy"
  run cat "${CALL_LOG}"
  assert_output "chezmoi apply ${HOME}/.config/dynet ${HOME}/.config/git/config"
}

@test "setup.sh skips the system layer inside a container unless asked" {
  printf '#!/bin/sh\nprintf "scz %%s\\n" "$*" >> %s\n' "${CALL_LOG}" > "${HOME}/.local/bin/scz"
  printf '#!/bin/sh\nexit 0\n' > "${HOME}/.local/bin/sudo"
  chmod +x "${HOME}/.local/bin/scz" "${HOME}/.local/bin/sudo"
  # dybatpho refreshes the sudo ticket from a background loop, whose sleep
  # otherwise holds the output of the test open for a minute.
  export DYBATPHO_PRIVILEGE_REFRESH=1

  container=podman run_setup '_apply_system_layer'
  assert_success
  assert_stderr --partial "pass --system"
  run cat "${CALL_LOG}"
  assert_output ""

  container=podman SYSTEM_LAYER=true run_setup '_apply_system_layer'
  assert_success
  run cat "${CALL_LOG}"
  assert_output --partial "scz apply"
}

@test "setup.sh stops with a clear message on a Bash older than 4.3" {
  [[ -x /bin/bash ]] || skip "no /bin/bash"
  # shellcheck disable=SC2016
  /bin/bash -c '((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3)))' \
    || skip "/bin/bash is already 4.3 or newer"

  # Told not to look for a newer Bash, so the message is what it shows.
  DOTFILES_SETUP_REEXEC=1 run --separate-stderr /bin/bash "${SETUP}" --help
  assert_failure
  assert_stderr --partial "needs Bash 4.3 or newer"
}
