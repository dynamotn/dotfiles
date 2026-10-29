# @file dyai_node.sh
# @brief Give a machine its dyai crew store signing key, kept in the secrets and trusted by the store
# @description A machine joining the crew store needs an SSH key it signs its
# events with (scripts/lib/dyai/docs/dyai-store.md). The first apply on a new
# machine makes one, adds it under `nodes.<code>` of the age-encrypted
# `secrets/data/personal/dyai.yaml.age` (so every later apply renders the same
# key, see home/.chezmoitemplates/dyai/node-key.tmpl), and adds its public half
# to `nodes/allowed_signers` on the store's main branch. The private key never
# touches the disk unencrypted outside its own target file: it travels from
# the key file to age through a pipe. Sourced (not executed); the caller
# sources dybatpho and dycrypt.sh first.
# shellcheck shell=bash

# A machine code: it becomes the signer's principal in allowed_signers.
DYAI_NODE_CODE_RE='^[A-Za-z0-9_-]+$'

#######################################
# @description Make the signing key pair of a machine, unless it is there
# @arg $1 string Path of the private key; the public one is `<path>.pub`
# @arg $2 string Machine code, the key's comment
# @exitcode 0 The pair exists, made now or before
#######################################
function dyai_node::keygen {
  local key code
  dybatpho::expect_args key code -- "$@"
  [[ "${code}" =~ ${DYAI_NODE_CODE_RE} ]] || dybatpho::die "not a machine code: ${code}"
  if dybatpho::is file "${key}" && dybatpho::is file "${key}.pub"; then
    return 0
  fi
  dybatpho::is command ssh-keygen || dybatpho::die "ssh-keygen is not installed"
  dybatpho::ensure_dir "${key%/*}" > /dev/null
  chmod 700 -- "${key%/*}"
  rm -f -- "${key}" "${key}.pub"
  # No passphrase: dyai signs unattended. The agent policy denies reading it.
  ssh-keygen -q -t ed25519 -N '' -C "${code}" -f "${key}" < /dev/null \
    || dybatpho::die "could not make the signing key ${key}"
  chmod 600 -- "${key}"
}

#######################################
# @description Keep a machine's two key pairs in the encrypted secrets, under nodes.<code>
# @arg $1 string Machine code
# @arg $2 string Path of the signing key
# @arg $3 string Path of the deploy key
# @arg $4 string The encrypted secrets file (created when missing)
# @arg $5 string The age identity key that reads and writes it
# @stdout `added` when the file changed, nothing otherwise
#######################################
function dyai_node::save_secret {
  local code signing deploy cipher identity
  dybatpho::expect_args code signing deploy cipher identity -- "$@"
  [[ "${code}" =~ ${DYAI_NODE_CODE_RE} ]] || dybatpho::die "not a machine code: ${code}"
  local current="nodes: {}" public deploy_public
  if dybatpho::is file "${cipher}"; then
    current="$(age -d -i "${identity}" "${cipher}")" || dybatpho::die "cannot decrypt ${cipher}"
  fi
  public="$(< "${signing}.pub")" || dybatpho::die "cannot read ${signing}.pub"
  deploy_public="$(< "${deploy}.pub")" || dybatpho::die "cannot read ${deploy}.pub"
  local stored_public stored_deploy
  stored_public="$(CODE="${code}" yq '.nodes[strenv(CODE)].public // ""' <<< "${current}")" || stored_public=""
  stored_deploy="$(CODE="${code}" yq '.nodes[strenv(CODE)].deploy_public // ""' <<< "${current}")" \
    || stored_deploy=""
  if [[ "${stored_public}" == "${public}" && "${stored_deploy}" == "${deploy_public}" ]]; then
    return 0
  fi
  # A key is added, never replaced: another key under the same code is the user's to settle.
  [[ -z "${stored_public}" || "${stored_public}" == "${public}" ]] \
    || dybatpho::die "the secrets hold another signing key for ${code}; remove nodes.${code} by hand to replace it"
  [[ -z "${stored_deploy}" || "${stored_deploy}" == "${deploy_public}" ]] \
    || dybatpho::die "the secrets hold another deploy key for ${code}; remove nodes.${code} by hand to replace it"
  local tmp signing_text deploy_text
  signing_text="$(< "${signing}")" || dybatpho::die "cannot read ${signing}"
  deploy_text="$(< "${deploy}")" || dybatpho::die "cannot read ${deploy}"
  dybatpho::ensure_dir "${cipher%/*}" > /dev/null
  # dyshellint disable=BSG046 renamed over the secrets file, so it must sit beside it; a failure removes it
  tmp="$(mktemp "${cipher}.XXXXXX")" || return 1
  # The private keys go to yq through the environment and to age through a
  # pipe: no plaintext copy lands on the disk.
  if ! CODE="${code}" SIGNING="${signing_text}" PUBLIC="${public}" DEPLOY="${deploy_text}" \
    DEPLOY_PUBLIC="${deploy_public}" yq '.nodes[strenv(CODE)] = {
      "signing": strenv(SIGNING) + "\n", "public": strenv(PUBLIC),
      "deploy": strenv(DEPLOY) + "\n", "deploy_public": strenv(DEPLOY_PUBLIC)}' <<< "${current}" \
    | age -e -a -i "${identity}" -o "${tmp}"; then
    rm -f -- "${tmp}"
    dybatpho::die "could not write the keys of ${code} into ${cipher}"
  fi
  mv -f -- "${tmp}" "${cipher}"
  printf 'added\n'
}

#######################################
# @description Print what a machine's store setup covers: a change to any of it sets it up again
# @arg $1 string URL of the store
# @arg $2 string Path of the public signing key
# @arg $3 string Path of the public deploy key
# @stdout One line: the URL and the two keys
#######################################
function dyai_node::stamp {
  local url signing deploy
  dybatpho::expect_args url signing deploy -- "$@"
  local a b
  a="$(cut -d' ' -f1,2 < "${signing}")" || return 1
  b="$(cut -d' ' -f1,2 < "${deploy}")" || return 1
  printf '%s %s %s\n' "${url}" "${a}" "${b}"
}

#######################################
# @description Tell whether glab can reach gitlab.com as you
# @noargs
# @exitcode 1 glab is missing, or not logged in yet
#######################################
function dyai_node::glab_ready {
  dybatpho::is command glab || return 1
  glab auth status --hostname gitlab.com &> /dev/null
}

#######################################
# @description Print a GitLab project path encoded for the API
# @arg $1 string Project path, such as group/name
#######################################
function __dyai_node_project_id {
  local project
  dybatpho::expect_args project -- "$@"
  printf '%s\n' "${project//\//%2F}"
}

#######################################
# @description Register a machine's deploy key on the store project, with write access (glab)
# @arg $1 string GitLab project path of the store
# @arg $2 string Machine code, in the key's title
# @arg $3 string Path of the public deploy key
# @stdout `added` or `enabled` when the project changed, nothing otherwise
#######################################
function dyai_node::register_deploy_key {
  local project code pub
  dybatpho::expect_args project code pub -- "$@"
  dybatpho::is command glab || dybatpho::die "glab is not installed; add the deploy key of ${code} by hand"
  local id key keys found
  id="$(__dyai_node_project_id "${project}")"
  key="$(cut -d' ' -f1,2 < "${pub}")" || dybatpho::die "cannot read ${pub}"
  keys="$(glab api --paginate "projects/${id}/deploy_keys")" \
    || dybatpho::die "glab cannot list the deploy keys of ${project}; is it logged in to gitlab.com?"
  # --paginate prints one array per page.
  keys="$(jq -cs 'add // []' <<< "${keys}")" || dybatpho::die "glab gave no JSON for the deploy keys of ${project}"
  # Matched on the key itself, not the title: the comment may differ.
  found="$(jq -r --arg k "${key}" '[.[] | select((.key | split(" ")[0:2] | join(" ")) == $k)
    | "\(.id) \(.can_push)"] | first // empty' <<< "${keys}")" || found=""
  if [[ -z "${found}" ]]; then
    glab api -X POST "projects/${id}/deploy_keys" -f "title=dyai ${code}" -f "key=${key}" -F can_push=true \
      > /dev/null || dybatpho::die "glab cannot add the deploy key of ${code} to ${project}"
    printf 'added\n'
  elif [[ "${found#* }" != true ]]; then
    glab api -X PUT "projects/${id}/deploy_keys/${found%% *}" -F can_push=true > /dev/null \
      || dybatpho::die "glab cannot give the deploy key of ${code} write access on ${project}"
    printf 'enabled\n'
  fi
}

#######################################
# @description Keep the store's main out of reach of every deploy key: protected,
# maintainers only, no force push (glab)
# @arg $1 string GitLab project path of the store
# @stdout `protected` when the project changed, nothing otherwise
#######################################
function dyai_node::protect_main {
  local project
  dybatpho::expect_args project -- "$@"
  dybatpho::is command glab || dybatpho::die "glab is not installed; protect main of ${project} by hand"
  local id branch err errfile
  id="$(__dyai_node_project_id "${project}")"
  dybatpho::create_temp errfile ".err" "dyai-node"
  if ! branch="$(glab api "projects/${id}/protected_branches/main" 2> "${errfile}")"; then
    err="$(< "${errfile}")" || err=""
    [[ "${err}" == *404* ]] || dybatpho::die "glab cannot read the protection of main on ${project}: ${err##*$'\n'}"
    glab api -X POST "projects/${id}/protected_branches" -f name=main \
      -F push_access_level=40 -F merge_access_level=40 -F allow_force_push=false > /dev/null \
      || dybatpho::die "glab cannot protect main on ${project}"
    printf 'protected\n'
    return 0
  fi
  # A deploy key that may push to main could trust any key: the store's trust is gone.
  if jq -e '[.push_access_levels[]? | select(.deploy_key_id != null)] | length > 0' <<< "${branch}" > /dev/null; then
    dybatpho::die "a deploy key may push to main of ${project}; remove it in Settings > Repository > Protected branches"
  fi
  if jq -e '.allow_force_push == true' <<< "${branch}" > /dev/null; then
    glab api -X PATCH "projects/${id}/protected_branches/main" -F allow_force_push=false > /dev/null \
      || dybatpho::die "glab cannot turn off force pushes to main on ${project}"
    printf 'protected\n'
  fi
}

#######################################
# @description Trust a machine's public key in the crew store: a line in nodes/allowed_signers on main
# @arg $1 string Machine code, the signer's principal
# @arg $2 string Path of the public key
# @arg $3 string URL of the store repository
# @stdout `added` when main moved, nothing otherwise
#######################################
function dyai_node::trust {
  local code pub url
  dybatpho::expect_args code pub url -- "$@"
  [[ "${code}" =~ ${DYAI_NODE_CODE_RE} ]] || dybatpho::die "not a machine code: ${code}"
  local key line work file existing remote
  key="$(cut -d' ' -f1,2 < "${pub}")" || dybatpho::die "cannot read ${pub}"
  line="${code} namespaces=\"git\" ${key}"
  # Removed on exit by dybatpho, and at once below on success.
  dybatpho::create_temp_dir work "dyai-node"
  remote="$(git ls-remote "${url}" refs/heads/main)" || dybatpho::die "cannot reach ${url}"
  if [[ -n "${remote}" ]]; then
    git clone -q --depth 1 --branch main "${url}" "${work}/store" || dybatpho::die "cannot clone ${url}"
  else
    # A store nobody set up yet: this machine writes its first main.
    git init -q -b main "${work}/store"
  fi
  file="${work}/store/nodes/allowed_signers"
  existing="$(awk -v c="${code}" '$1 == c' "${file}" 2> /dev/null)" || existing=""
  if [[ "${existing}" == "${line}" ]]; then
    rm -rf -- "${work:?}"
    return 0
  fi
  # Trust is not replaced behind anyone's back: a code with another key is the user's to settle.
  [[ -z "${existing}" ]] \
    || dybatpho::die "${url} trusts another key for ${code}; edit nodes/allowed_signers on main by hand"
  dybatpho::ensure_dir "${file%/*}" > /dev/null
  printf '%s\n' "${line}" >> "${file}"
  git -C "${work}/store" add nodes/allowed_signers
  git -C "${work}/store" commit -q -m "feat(nodes): trust ${code}" || dybatpho::die "cannot commit the key of ${code}"
  git -C "${work}/store" push -q "${url}" HEAD:refs/heads/main \
    || dybatpho::die "cannot push the key of ${code} to ${url}; main may be protected from your account"
  rm -rf -- "${work:?}"
  printf 'added\n'
}
