# dyshellint disable=SC2154 DOTFILES_DIR and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  command -v age &> /dev/null || skip "age not found"
  command -v ssh-keygen &> /dev/null || skip "ssh-keygen not found"
  . "${DOTFILES_DIR}/scripts/lib/dyai_node.sh"
  # A throwaway age identity and store: the real secrets are never read here.
  ID="${BATS_TEST_TMPDIR}/id.key"
  age-keygen -o "${ID}" 2> /dev/null
  CIPHER="${BATS_TEST_TMPDIR}/secrets/personal/dyai.yaml.age"
  KEY="${BATS_TEST_TMPDIR}/node/signing"
  DEPLOY="${BATS_TEST_TMPDIR}/node/deploy"
  STORE="${BATS_TEST_TMPDIR}/store.git"
  git init -q --bare -b main "${STORE}"
  # A git hook running the suite exports its own repository's GIT_DIR.
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  git config --global user.email t@t
  git config --global user.name t
}

function _secret {
  age -d -i "${ID}" "${CIPHER}"
}

function _signers {
  git -C "${STORE}" show main:nodes/allowed_signers
}

@test "keygen makes a private pair and keeps one that is there" {
  dyai_node::keygen "${KEY}" laptop
  [[ -f "${KEY}" && -f "${KEY}.pub" ]]
  [[ "$(stat -c %a "${KEY}" 2> /dev/null || stat -f %Lp "${KEY}")" == 600 ]]
  local before
  before="$(< "${KEY}.pub")"
  dyai_node::keygen "${KEY}" laptop
  [[ "$(< "${KEY}.pub")" == "${before}" ]]
  run dyai_node::keygen "${KEY}" "bad code"
  assert_failure
}

@test "save_secret adds both pairs once, under the machine's code, and keeps the others" {
  dyai_node::keygen "${KEY}" laptop
  dyai_node::keygen "${DEPLOY}" laptop
  run --separate-stderr dyai_node::save_secret laptop "${KEY}" "${DEPLOY}" "${CIPHER}" "${ID}"
  assert_success
  assert_output added
  dyai_node::keygen "${BATS_TEST_TMPDIR}/pc/signing" pc
  dyai_node::keygen "${BATS_TEST_TMPDIR}/pc/deploy" pc
  dyai_node::save_secret pc "${BATS_TEST_TMPDIR}/pc/signing" "${BATS_TEST_TMPDIR}/pc/deploy" "${CIPHER}" "${ID}" \
    > /dev/null
  run _secret
  [[ "$(yq '.nodes | keys | join(" ")' <<< "${output}")" == "laptop pc" ]]
  [[ "$(yq '.nodes.laptop.public' <<< "${output}")" == "$(< "${KEY}.pub")" ]]
  [[ "$(yq '.nodes.laptop.signing' <<< "${output}")" == "$(< "${KEY}")" ]]
  [[ "$(yq '.nodes.laptop.deploy_public' <<< "${output}")" == "$(< "${DEPLOY}.pub")" ]]
  [[ "$(yq '.nodes.laptop.deploy' <<< "${output}")" == "$(< "${DEPLOY}")" ]]
  # Already there: nothing is written.
  run --separate-stderr dyai_node::save_secret laptop "${KEY}" "${DEPLOY}" "${CIPHER}" "${ID}"
  assert_success
  assert_output ""
}

@test "save_secret never replaces another key of the same machine" {
  dyai_node::keygen "${KEY}" laptop
  dyai_node::keygen "${DEPLOY}" laptop
  dyai_node::save_secret laptop "${KEY}" "${DEPLOY}" "${CIPHER}" "${ID}" > /dev/null
  rm -f "${KEY}" "${KEY}.pub"
  dyai_node::keygen "${KEY}" laptop
  run --separate-stderr dyai_node::save_secret laptop "${KEY}" "${DEPLOY}" "${CIPHER}" "${ID}"
  assert_failure
  [[ "${stderr}" == *"another signing key for laptop"* ]]
}

@test "save_secret leaves no plaintext beside the secrets file" {
  dyai_node::keygen "${KEY}" laptop
  dyai_node::keygen "${DEPLOY}" laptop
  dyai_node::save_secret laptop "${KEY}" "${DEPLOY}" "${CIPHER}" "${ID}" > /dev/null
  run ls -A "${CIPHER%/*}"
  assert_output dyai.yaml.age
  run grep -c 'PRIVATE KEY' "${CIPHER}"
  assert_output 0
}

@test "trust starts main in an empty store, then adds each machine once" {
  dyai_node::keygen "${KEY}" laptop
  run --separate-stderr dyai_node::trust laptop "${KEY}.pub" "${STORE}"
  assert_success
  assert_output added
  run _signers
  assert_output "laptop namespaces=\"git\" $(cut -d' ' -f1,2 < "${KEY}.pub")"
  run --separate-stderr dyai_node::trust laptop "${KEY}.pub" "${STORE}"
  assert_output ""
  dyai_node::keygen "${BATS_TEST_TMPDIR}/pc/signing" pc
  dyai_node::trust pc "${BATS_TEST_TMPDIR}/pc/signing.pub" "${STORE}" > /dev/null
  run _signers
  [[ "$(awk '{print $1}' <<< "${output}" | paste -sd' ' -)" == "laptop pc" ]]
}

@test "trust never replaces the key the store trusts for a machine" {
  dyai_node::keygen "${KEY}" laptop
  dyai_node::trust laptop "${KEY}.pub" "${STORE}" > /dev/null
  rm -f "${KEY}" "${KEY}.pub"
  dyai_node::keygen "${KEY}" laptop
  run --separate-stderr dyai_node::trust laptop "${KEY}.pub" "${STORE}"
  assert_failure
  [[ "${stderr}" == *"trusts another key for laptop"* ]]
}

@test "a key trusted this way signs commits the store accepts" {
  dyai_node::keygen "${KEY}" laptop
  dyai_node::trust laptop "${KEY}.pub" "${STORE}" > /dev/null
  local repo="${BATS_TEST_TMPDIR}/r" signers="${BATS_TEST_TMPDIR}/allowed"
  _signers > "${signers}"
  git init -q "${repo}"
  git -C "${repo}" -c gpg.format=ssh -c "user.signingkey=${KEY}" commit -q -S --allow-empty -m signed
  run git -C "${repo}" -c gpg.format=ssh -c "gpg.ssh.allowedSignersFile=${signers}" log -1 --format='%G? %GS'
  assert_output "G laptop"
}

@test "save_secret adds a deploy key to a machine that has only its signing key" {
  dyai_node::keygen "${KEY}" laptop
  dyai_node::keygen "${DEPLOY}" laptop
  # An entry from before deploy keys.
  mkdir -p "${CIPHER%/*}"
  CODE=laptop PUB="$(< "${KEY}.pub")" yq -n '.nodes[strenv(CODE)].public = strenv(PUB)' \
    | age -e -a -i "${ID}" -o "${CIPHER}"
  run --separate-stderr dyai_node::save_secret laptop "${KEY}" "${DEPLOY}" "${CIPHER}" "${ID}"
  assert_output added
  run _secret
  [[ "$(yq '.nodes.laptop.deploy_public' <<< "${output}")" == "$(< "${DEPLOY}.pub")" ]]
}

# A glab stand-in: GET answers come from files under GLAB_DIR, every call is logged.
function _glab {
  GLAB_DIR="${BATS_TEST_TMPDIR}/glab"
  mkdir -p "${GLAB_DIR}" "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/glab" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${GLAB_DIR}/calls"
case "\$*" in
  *"-X "*) echo '{}' ;;
  *deploy_keys*) cat "${GLAB_DIR}/keys.json" ;;
  *protected_branches/main*)
    if [[ -f "${GLAB_DIR}/main.json" ]]; then cat "${GLAB_DIR}/main.json"; else echo "404 Not found" >&2; exit 1; fi ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/glab"
  PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

@test "register_deploy_key adds the key with write access, once" {
  _glab
  dyai_node::keygen "${DEPLOY}" laptop
  echo '[]' > "${GLAB_DIR}/keys.json"
  run --separate-stderr dyai_node::register_deploy_key group/store laptop "${DEPLOY}.pub"
  assert_output added
  run grep -c 'X POST projects/group%2Fstore/deploy_keys -f title=dyai laptop -f key=ssh-ed25519 .* -F can_push=true' \
    "${GLAB_DIR}/calls"
  assert_output 1
  jq -cn --arg k "$(cut -d' ' -f1,2 < "${DEPLOY}.pub") other comment" '[{id: 7, key: $k, can_push: true}]' \
    > "${GLAB_DIR}/keys.json"
  run --separate-stderr dyai_node::register_deploy_key group/store laptop "${DEPLOY}.pub"
  assert_output ""
}

@test "register_deploy_key gives write access to a key registered read-only" {
  _glab
  dyai_node::keygen "${DEPLOY}" laptop
  jq -cn --arg k "$(cut -d' ' -f1,2 < "${DEPLOY}.pub")" '[{id: 7, key: $k, can_push: false}]' > "${GLAB_DIR}/keys.json"
  run --separate-stderr dyai_node::register_deploy_key group/store laptop "${DEPLOY}.pub"
  assert_output enabled
  run grep -c 'X PUT projects/group%2Fstore/deploy_keys/7 -F can_push=true' "${GLAB_DIR}/calls"
  assert_output 1
}

@test "protect_main protects an unprotected main for maintainers, without force push" {
  _glab
  run --separate-stderr dyai_node::protect_main group/store
  assert_output protected
  run grep -c 'X POST projects/group%2Fstore/protected_branches -f name=main -F push_access_level=40' \
    "${GLAB_DIR}/calls"
  assert_output 1
}

@test "protect_main refuses a main a deploy key may push to" {
  _glab
  local main='{"name":"main","allow_force_push":false,'
  main+='"push_access_levels":[{"access_level":40},{"deploy_key_id":7}]}'
  printf '%s\n' "${main}" > "${GLAB_DIR}/main.json"
  run --separate-stderr dyai_node::protect_main group/store
  assert_failure
  [[ "${stderr}" == *"a deploy key may push to main"* ]]
}

@test "protect_main turns off force pushes and leaves a sound main alone" {
  _glab
  echo '{"name":"main","allow_force_push":true,"push_access_levels":[{"access_level":40}]}' > "${GLAB_DIR}/main.json"
  run --separate-stderr dyai_node::protect_main group/store
  assert_output protected
  echo '{"name":"main","allow_force_push":false,"push_access_levels":[{"access_level":40}]}' > "${GLAB_DIR}/main.json"
  run --separate-stderr dyai_node::protect_main group/store
  assert_output ""
}
