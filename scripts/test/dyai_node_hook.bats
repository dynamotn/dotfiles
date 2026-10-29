# dyshellint disable=SC2154 DOTFILES_DIR and BATS_TEST_TMPDIR come from bats and test_helper
# The apply hook of the dyai store keys, rendered from a sandbox source: its
# secrets tree, age identity, store and glab are all throwaway stand-ins.
setup() {
  load test_helper
  setup_dotfiles_test_env
  command -v chezmoi &> /dev/null || skip "chezmoi not found"
  command -v age &> /dev/null || skip "age not found"
  command -v ssh-keygen &> /dev/null || skip "ssh-keygen not found"
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  SANDBOX="${BATS_TEST_TMPDIR}/dotfiles"
  mkdir -p "${SANDBOX}/home/.chezmoiscripts" "${SANDBOX}/scripts/lib" "${SANDBOX}/secrets/data"
  cp "${DOTFILES_DIR}/home/.chezmoiscripts/run_after_04-setup-dyai-node.sh.tmpl" "${SANDBOX}/home/.chezmoiscripts/"
  cp "${DOTFILES_DIR}/scripts/lib/dycrypt.sh" "${DOTFILES_DIR}/scripts/lib/dyai_node.sh" "${SANDBOX}/scripts/lib/"
  ln -s "${DOTFILES_DIR}/scripts/lib/dybatpho" "${SANDBOX}/scripts/lib/dybatpho"
  git init -q -b main "${SANDBOX}/secrets/data"
  git config --global user.email t@t
  git config --global user.name t
  # The personal identity dycrypt reads, private as it checks.
  mkdir -p "${HOME}/.config/chezmoi"
  chmod 700 "${HOME}/.config/chezmoi"
  age-keygen -o "${HOME}/.config/chezmoi/personal.key" 2> /dev/null
  chmod 600 "${HOME}/.config/chezmoi/personal.key"
  # The store: gitlab.com is a bare repository on disk.
  STORE="${BATS_TEST_TMPDIR}/store.git"
  git init -q --bare -b main "${STORE}"
  git config --global "url.file://${STORE}.insteadOf" "git@gitlab.com:group/store.git"
  mkdir -p "${HOME}/.config/dyai"
  printf 'global:\n  crew:\n    store:\n      backend: git\n      url: git@gitlab.com:group/store.git\n' \
    > "${HOME}/.config/dyai/config.yaml"
  CONFIG="${BATS_TEST_TMPDIR}/chezmoi.yaml"
  printf 'sourceDir: "%s/home"\ndata:\n  bash: "%s"\n  code: laptop\n  kind: laptop\n  decryptPersonal: true\n' "${SANDBOX}" "$(command -v bash)" \
    > "${CONFIG}"
  # glab: logged in when GLAB_OK exists, every call logged.
  GLAB_DIR="${BATS_TEST_TMPDIR}/glab"
  mkdir -p "${GLAB_DIR}" "${BATS_TEST_TMPDIR}/bin"
  echo '[]' > "${GLAB_DIR}/keys.json"
  cat > "${BATS_TEST_TMPDIR}/bin/glab" << EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "${GLAB_DIR}/calls"
case "\$*" in
  "auth status"*) [[ -e "${GLAB_DIR}/ok" ]] ;;
  *"-X "*) echo '{}' ;;
  *deploy_keys*) cat "${GLAB_DIR}/keys.json" ;;
  *protected_branches/main*) echo "404 Not found" >&2; exit 1 ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/glab"
  PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  HOOK="${BATS_TEST_TMPDIR}/hook.sh"
  chezmoi execute-template --config "${CONFIG}" --source "${SANDBOX}/home" \
    --file "${SANDBOX}/home/.chezmoiscripts/run_after_04-setup-dyai-node.sh.tmpl" > "${HOOK}"
}

function _signers {
  git -C "${STORE}" show main:nodes/allowed_signers
}

@test "hook: before glab is logged in it keeps the keys, warns, and leaves the apply alone" {
  run --separate-stderr bash "${HOOK}"
  assert_success
  [[ "${stderr}" == *"glab auth login"* ]]
  [[ -f "${HOME}/.config/dyai/node/signing" && -f "${HOME}/.config/dyai/node/deploy" ]]
  [[ -f "${SANDBOX}/secrets/data/personal/dyai.yaml.age" ]]
  run git -C "${SANDBOX}/secrets/data" log --format=%s
  assert_output "feat(dyai): keep the store keys of laptop"
  [[ ! -e "${HOME}/.local/state/dyai/node-setup" ]]
  run git -C "${STORE}" rev-parse -q --verify main
  assert_failure
}

@test "hook: once glab is logged in the next apply finishes, then stops at its stamp" {
  bash "${HOOK}" 2> /dev/null
  touch "${GLAB_DIR}/ok"
  run --separate-stderr bash "${HOOK}"
  assert_success
  run grep -c 'X POST projects/group%2Fstore/deploy_keys' "${GLAB_DIR}/calls"
  assert_output 1
  run grep -c 'X POST projects/group%2Fstore/protected_branches' "${GLAB_DIR}/calls"
  assert_output 1
  run _signers
  assert_output "laptop namespaces=\"git\" $(cut -d' ' -f1,2 < "${HOME}/.config/dyai/node/signing.pub")"
  [[ -f "${HOME}/.local/state/dyai/node-setup" ]]
  # Done: a later apply touches neither glab nor the secrets.
  rm -f "${GLAB_DIR}/calls"
  run --separate-stderr bash "${HOOK}"
  assert_success
  [[ ! -e "${GLAB_DIR}/calls" ]]
  run git -C "${SANDBOX}/secrets/data" rev-list --count HEAD
  assert_output 1
}

@test "hook: a GitLab that fails costs a warning, not the apply, and the next apply tries again" {
  touch "${GLAB_DIR}/ok"
  # The store cannot be reached: trust fails after glab's steps.
  git config --global "url.file://${BATS_TEST_TMPDIR}/nowhere.git.insteadOf" "git@gitlab.com:group/store.git"
  git config --global --unset "url.file://${STORE}.insteadOf"
  run --separate-stderr bash "${HOOK}"
  assert_success
  [[ "${stderr}" == *"the next chezmoi apply tries again"* ]]
  [[ ! -e "${HOME}/.local/state/dyai/node-setup" ]]
}

@test "hook: a machine on the local store gets no keys" {
  printf 'global:\n  crew:\n    timeout: 60\n' > "${HOME}/.config/dyai/config.yaml"
  run --separate-stderr bash "${HOOK}"
  assert_success
  [[ ! -e "${HOME}/.config/dyai/node" ]]
}
