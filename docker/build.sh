#!/usr/bin/env bash
# @file build.sh
# @brief Build container and setup dotfiles
# @description Run inside the container image build: install the certificates
# and packages the image needs, apply the dotfiles for the identities carried
# as build secrets, then drop both the secrets and the build-only packages.
# The public image carries no `age_passphrases` secret and is built with no
# identity at all.
SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")/../scripts")"
# The build context is the checkout scripts/docker.sh ran from, which fetched
# the submodule before it could source the library itself.
if [[ ! -f "${SCRIPT_DIR}/lib/dybatpho/init.sh" ]]; then
  printf 'dybatpho is missing from the build context; run: git submodule update --init scripts/lib/dybatpho\n' >&2
  exit 1
fi
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../scripts/lib/dybatpho/init.sh
. "${SCRIPT_DIR}/lib/dybatpho/init.sh" --modules privilege
dybatpho::register_common_handlers
# Where BuildKit mounts the build secrets; tests point it elsewhere.
SECRETS_DIR="${DOCKER_BUILD_SECRETS_DIR:-/run/secrets}"

#######################################
# @description Install custom SSL certificates if provided in Docker secrets.
# @noargs
#######################################
function _install_ssl_certs {
  local certificate="${SECRETS_DIR}/ssl_cert"
  dybatpho::is file "${certificate}" || return 0
  local folder update_cmd
  if dybatpho::is command apk; then
    folder="/usr/local/share/ca-certificates"
    update_cmd="update-ca-certificates"
  elif dybatpho::is command pacman; then
    folder="/etc/ca-certificates/trust-source/anchors"
    update_cmd="update-ca-trust"
  else
    dybatpho::die "No known trust store to install ${certificate} into"
  fi
  # The system trust store is root-owned.
  dybatpho::privilege_run -- cp "${certificate}" "${folder}/ssl_decryption.crt"
  dybatpho::privilege_run -- "${update_cmd}"
}

#######################################
# @description Install packages required for setting up dotfiles.
# @noargs
#######################################
function _install_packages {
  if dybatpho::is command pacman; then
    # Choose mirror for VN
    printf '%s\n' "Server = https://mirror.bizflycloud.vn/archlinux/\$repo/os/\$arch" \
      | dybatpho::privilege_run -- tee /etc/pacman.d/mirrorlist > /dev/null
    # One transaction that upgrades with the install: `-Sy` and installs
    # after it are a partial upgrade. expect is container only; git, curl and
    # openssh clone code; chezmoi and age apply the dotfiles.
    dybatpho::privilege_run -- pacman -Syu --needed --noconfirm \
      expect git curl openssh chezmoi age
  elif dybatpho::is command apk; then
    dybatpho::privilege_run -- apk update
    # Container only tools
    dybatpho::privilege_run -- apk add --no-cache expect
    # GNU compatible tools
    dybatpho::privilege_run -- apk add --no-cache coreutils grep file
    # Install for cloning code
    dybatpho::privilege_run -- apk add --no-cache git curl openssh
    # Install chezmoi tools
    dybatpho::privilege_run -- apk add --no-cache chezmoi age
  fi
}

#######################################
# @description Print the identities named in the `age_passphrases` build
# secret, one `name=passphrase` per line, as the comma separated list
# setup.sh takes. Prints nothing when the secret is absent.
# @noargs
# @stdout Identities separated by `,`, possibly empty
#######################################
function _read_identities {
  local secret="${SECRETS_DIR}/age_passphrases"
  if ! dybatpho::is file "${secret}"; then
    dybatpho::info "No age_passphrases secret: building without any identity" >&2
    return 0
  fi
  local passphrases key identities=""
  # The build secret is mounted root-only.
  passphrases="$(dybatpho::privilege_run -- cat "${secret}")"
  # Read line by line: split as words, a passphrase holding spaces or glob
  # characters broke apart or expanded to file names.
  while IFS='=' read -r key _; do
    dybatpho::string_is_blank "${key}" && continue
    identities+="${key},"
  done <<< "${passphrases}"
  printf '%s\n' "${identities}"
}

#######################################
# @description Main function to setup dotfiles.
# @noargs
#######################################
function _main {
  _install_ssl_certs
  _install_packages

  # Pin the host keys of the public forges, published on their documentation
  # pages, and trust other hosts on first use: the build has the secrets
  # mounted, so a swapped github.com or gitlab.com must not be accepted.
  local known_hosts
  known_hosts="$(realpath "$(dybatpho::path_dirname "${BASH_SOURCE[0]}")")/known_hosts"
  export GIT_SSH_COMMAND="ssh -oStrictHostKeyChecking=accept-new -oUserKnownHostsFile=${known_hosts}"

  # An image build does not always look like a container from the inside:
  # BuildKit leaves no /.dockerenv, and cgroup v2 names no runtime. Say so,
  # for the chezmoi configuration and for setup.sh.
  export container="${container:-docker}"
  export DOTFILES_KIND="container"

  local identities
  identities="$(_read_identities)"
  # The system layer is skipped in containers by default; an image is built
  # with it, as it always was, since the files a container cannot take are
  # ignored there.
  local -a setup_args=(--use-default --system)
  if ! dybatpho::string_is_blank "${identities}"; then
    setup_args+=("-i${identities}")
  fi
  "${SCRIPT_DIR}/setup.sh" "${setup_args[@]}"

  # Delete sensitive data
  rm -rf "${HOME}"/.config/chezmoi/*.key "${HOME}/Dotfiles/secrets"
  # Delete unnecessary data
  rm -rf "${HOME}/.cache/chezmoi" "${HOME}"/Dotfiles/.git*
  # Uninstall packages
  if dybatpho::is command pacman; then
    dybatpho::privilege_run -- pacman -Rnsc --noconfirm chezmoi
  elif dybatpho::is command apk; then
    dybatpho::privilege_run -- apk del chezmoi
  fi
}

# Sourced, as by its tests, it only defines the functions above.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  _main
fi
