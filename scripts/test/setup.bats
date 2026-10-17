setup() {
  load test_helper
  setup_dotfiles_test_env
  SETUP="${DOTFILES_DIR}/scripts/setup.sh"
  CALL_LOG="${BATS_TEST_TMPDIR}/calls.log"
  : > "${CALL_LOG}"
  # A sandbox stands in for the repository: `_generate_chezmoi_config` writes
  # into `home/` of the root it is given, and a test must never write there.
  SANDBOX="${BATS_TEST_TMPDIR}/dotfiles"
  mkdir -p "${SANDBOX}/home"
  cp "${DOTFILES_DIR}/.chezmoi.yaml.tmpl" "${DOTFILES_DIR}/.chezmoiroot" \
    "${DOTFILES_DIR}/.chezmoiversion" "${SANDBOX}/"
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
    '_generate_chezmoi_config; _chezmoi_init_args; chezmoi "${CHEZMOI_INIT_ARGS[@]}" < /dev/null'
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

@test "setup.sh exports the proxy and its exceptions from the chezmoi data" {
  # `// empty` is jq, not yq: the parse error was hidden, so no_proxy was
  # never exported.
  cat > "${HOME}/.local/bin/chezmoi" << 'EOF'
#!/bin/sh
printf '{"httpProxy":"http://proxy:3128","noProxyAddresses":["localhost","10.0.0.0/8"]}\n'
EOF
  chmod +x "${HOME}/.local/bin/chezmoi"
  run_setup '_export_proxy; printf "%s|%s|%s\n" "${http_proxy}" "${https_proxy}" "${no_proxy}"'
  assert_success
  assert_output "http://proxy:3128|http://proxy:3128|localhost,10.0.0.0/8"
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
