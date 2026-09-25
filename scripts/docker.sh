#!/usr/bin/env bash
# @file docker.sh
# @brief Build a toolbox container image for one identity
# @description The images differ only in registry name, identity, base
#   distribution and which secrets they need. Everything else is shared.
# @arg $1 string Target: public, personal, personal-arch, or enterprise-<CODE>
# @env GITHUB_TOKEN Token passed to the build as a secret
set -Eeuo pipefail

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

#######################################
# @description Print usage and exit
#######################################
function _usage {
  echo "Usage: ${0##*/} <public|personal|personal-arch|enterprise-CODE>" >&2
  exit 1
}

target="${1:-}"
[[ -n "${target}" ]] || _usage

dockerfile="${REPO_DIR}/docker/Dockerfile.alpine"
build_args=()
secrets=(--secret "id=github_token,env=GITHUB_TOKEN")

case "${target}" in
  public)
    image="dynamotn/toolbox"
    export TOOLBOX_TYPE=""
    ;;
  personal)
    image="git.dynamotn.dev/config/dotfiles"
    export TOOLBOX_TYPE="personal"
    AGE_PASSPHRASES="personal=$(rbw get 'Age Dotfiles')"
    export AGE_PASSPHRASES
    build_args+=(--build-arg IDENTITIES="personal")
    secrets+=(--secret "id=age_passphrases,env=AGE_PASSPHRASES")
    ;;
  personal-arch)
    image="git.dynamotn.dev/config/dotfiles:arch"
    dockerfile="${REPO_DIR}/docker/Dockerfile.arch"
    export TOOLBOX_TYPE="personal"
    AGE_PASSPHRASES="personal=$(rbw get 'Age Dotfiles')"
    export AGE_PASSPHRASES
    secrets+=(--secret "id=age_passphrases,env=AGE_PASSPHRASES")
    ;;
  enterprise-*)
    enterprise="${target#enterprise-}"
    image="git.example.com/dynamo/toolbox:${enterprise}"
    export TOOLBOX_TYPE="${enterprise}"
    AGE_PASSPHRASES="${enterprise}=$(rbw get 'Age Dotfiles' --field "${enterprise}")"
    export AGE_PASSPHRASES
    SSL_CERT="$(
      age -d -i "${HOME}/.config/chezmoi/enterprise-${enterprise}.key" \
        "${REPO_DIR}/secrets/data/enterprise-${enterprise}/ssl.crt.age"
    )"
    export SSL_CERT
    secrets+=(--secret "id=age_passphrases,env=AGE_PASSPHRASES")
    secrets+=(--secret "id=ssl_cert,env=SSL_CERT")
    ;;
  *)
    _usage
    ;;
esac

# Quoted "~" never expands, so the original PATH entry did nothing.
export PATH="${HOME}/.local/bin:${PATH}"

gomplate -f "${REPO_DIR}/.dockerignore.tmpl" -o "${REPO_DIR}/.dockerignore"

docker build --network=host \
  "${secrets[@]}" \
  "${build_args[@]}" \
  --no-cache \
  -f "${dockerfile}" \
  -t "${image}" "${REPO_DIR}"
