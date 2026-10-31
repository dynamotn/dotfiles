#!/usr/bin/env bash
# @file setup.sh
# @brief Setup your machine from dotfiles
# @description Bring a fresh machine up to this repository: fetch the dybatpho
# submodule, install the tools chezmoi itself needs, generate the chezmoi
# configuration from its template and apply the dotfiles in order.
#
# Without a terminal, on CI or inside a container, chezmoi takes the default
# answer of every question instead of prompting. The root-owned system layer
# is skipped inside a container unless `--system` asks for it.

# dybatpho needs Bash 4.3 or newer, and a fresh macOS runs Bash 3.2 as `bash`.
# Everything up to the `fi` must therefore parse and run on Bash 3.2: it hands
# the script to a newer Homebrew Bash when there is one, and stops otherwise.
if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3))); then
  if [[ "${BASH_SOURCE[0]}" == "$0" && -z "${DOTFILES_SETUP_REEXEC:-}" ]]; then
    for newer_bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
      if [[ -x "${newer_bash}" ]]; then
        export DOTFILES_SETUP_REEXEC="${newer_bash}"
        exec "${newer_bash}" "${BASH_SOURCE[0]}" "$@"
      fi
    done
  fi
  printf 'setup.sh needs Bash 4.3 or newer, but runs on %s.\n' "${BASH_VERSION}" >&2
  printf 'Install it first, e.g. with scripts/prerequisite.sh, then run it again.\n' >&2
  exit 1
fi

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
# The library lives in a submodule, which a fresh clone or a new worktree
# does not populate. Fetch it before sourcing, or nothing below is defined.
if [[ ! -f "${SCRIPT_DIR}/lib/dybatpho/init.sh" ]]; then
  git -C "${SCRIPT_DIR}/.." submodule update --init "${SCRIPT_DIR}/lib/dybatpho"
fi
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/dybatpho/init.sh
. "${SCRIPT_DIR}/lib/dybatpho/init.sh" --modules cli network archive array privilege semver file
dybatpho::register_common_handlers
ROOT_DIR="$(dybatpho::path_join "${SCRIPT_DIR}" "..")"
ROOT_DIR="$(dybatpho::path_normalize "${ROOT_DIR}")"
BIN_DIR="$(dybatpho::path_join "${HOME}" ".local" "bin")"
BIN_DIR="$(dybatpho::ensure_dir "${BIN_DIR}")"
export PATH="${BIN_DIR}:${PATH}"
# The questions of `.chezmoi.yaml.tmpl` that `--identities` answers. chezmoi
# matches `--promptBool` and `--promptMultichoice` on the prompt text, so these
# must stay identical to the template, which scripts/test/setup.bats checks.
# A machine listed in home/.chezmoidata/machines.yaml is not asked them: its
# stored answers win over these.
PROMPT_PERSONAL="Do you want to decrypt personal's secrets (y/n)"
PROMPT_ENTERPRISE="Which company's secrets do you want to decrypt"

#######################################
# @description Spec of setup.sh
# @noargs
#######################################
function _spec_main {
  dybatpho::opts::setup "Setup your machine from dotfiles" MAIN_ARGS action:"_main"
  dybatpho::opts::param "Log level" LOG_LEVEL --log-level -l init:="info" \
    validate:"dybatpho::validate_log_level \$OPTARG"
  dybatpho::opts::flag "Use default values of chezmoi" USE_DEFAULT --use-default -d on:true off:false init:="false"
  dybatpho::opts::param "List of identities to decrypt, separated by \`,\`" IDENTITIES --identities -i optional:true on:
  dybatpho::opts::flag "Apply the root-owned system layer even inside a container" SYSTEM_LAYER --system -s \
    on:true off:false init:="false"
  dybatpho::opts::disp "Show help" --help -h action:"dybatpho::generate_help _spec_main"
}

#######################################
# @description Install binary version of chezmoi
# @env BIN_DIR Directory to install binary
# @noargs
#######################################
function _install_chezmoi {
  dybatpho::info "Installing chezmoi to ${BIN_DIR}"
  # Fetched to a file first, so a failed download stops here instead of
  # handing an empty script to `sh`.
  local installer
  dybatpho::create_temp installer ".sh"
  dybatpho::curl_download "https://get.chezmoi.io" "${installer}"
  sh "${installer}" -b "${BIN_DIR}"
}

#######################################
# @description Install binary version of age
# @env BIN_DIR Directory to install binary
# @noargs
#######################################
function _install_age {
  dybatpho::info "Installing age to ${BIN_DIR}"
  dybatpho::require "tar"
  local archive os arch
  os="$(dybatpho::goos)"
  arch="$(dybatpho::goarch)"
  dybatpho::create_temp archive ".tar.gz"
  dybatpho::curl_download "https://dl.filippo.io/age/latest?for=${os}/${arch}" "${archive}"
  dybatpho::archive_extract "${archive}" "${BIN_DIR}" 1
}

#######################################
# @description Install binary version of yq
# @env BIN_DIR Directory to install binary
# @noargs
#######################################
function _install_yq {
  dybatpho::info "Installing yq to ${BIN_DIR}"
  local yq_path os arch
  yq_path=$(dybatpho::path_join "${BIN_DIR}" "yq")
  os="$(dybatpho::goos)"
  arch="$(dybatpho::goarch)"
  local yq_url="https://github.com/mikefarah/yq/releases/latest/download"
  yq_url+="/yq_${os}_${arch}"
  dybatpho::curl_download "${yq_url}" "${yq_path}"
  chmod +x "${yq_path}"
}

#######################################
# @description Return success when this runs inside a container, dev
# containers included, which dybatpho does not recognise on their own
# @noargs
# @exitcode 0 Inside a container
# @exitcode 1 On a host
#######################################
function _is_container {
  dybatpho::is_container && return 0
  [[ -n "${CODESPACES:-}" || -n "${REMOTE_CONTAINERS:-}" || -n "${DEVCONTAINER:-}" ]]
}

#######################################
# @description Return success when nobody can answer a prompt: stdin is not a
# terminal, or this runs on CI or inside a container
# @noargs
# @exitcode 0 Prompts must take their defaults
# @exitcode 1 Prompts may ask
#######################################
function _is_unattended {
  ! dybatpho::is_tty stdin || dybatpho::is_ci || _is_container
}

#######################################
# @description Return success when the installed chezmoi is at least the
# version `.chezmoiversion` asks for
# @env ROOT_DIR Root of the dotfiles repository
# @noargs
# @exitcode 0 chezmoi is installed and recent enough
# @exitcode 1 It is missing, older, or does not say its version
#######################################
function _chezmoi_is_recent {
  local version_file required installed order
  version_file="$(dybatpho::path_join "${ROOT_DIR}" ".chezmoiversion")"
  required="$(< "${version_file}")"
  required="$(dybatpho::trim "${required}")"
  installed="$(dybatpho::command_version chezmoi)" || return 1
  installed="$(dybatpho::semver_coerce "${installed}")"
  order="$(dybatpho::semver_compare "${installed}" "${required}")"
  [[ "${order}" != "-1" ]]
}

#######################################
# @description Build the arguments of `chezmoi init`, answering the decryption
# questions from `--identities`. They are answered through chezmoi's own
# `--promptBool` and `--promptMultichoice`, which the template cannot drift
# away from unnoticed the way the text replacements this replaces did.
# @env ROOT_DIR Root of the dotfiles repository
# @env IDENTITIES Comma separated list of identities to decrypt
# @env USE_DEFAULT Whether every other question takes its default
# @set CHEZMOI_INIT_ARGS Array of arguments, `init` included
# @noargs
#######################################
# dyshellint disable=SC2310 the predicates of this script are meant to be tested here
function _chezmoi_init_args {
  CHEZMOI_INIT_ARGS=(init --source "${ROOT_DIR}")
  if _is_unattended; then
    dybatpho::info "No one to answer prompts here, so chezmoi takes the defaults"
    CHEZMOI_INIT_ARGS+=(--promptDefaults --no-tty)
  elif dybatpho::is true "${USE_DEFAULT:-false}"; then
    CHEZMOI_INIT_ARGS+=(--promptDefaults)
  else
    dybatpho::info "Please answer the following questions"
    CHEZMOI_INIT_ARGS+=(--prompt)
  fi

  # Blank fields, such as the one a trailing `,` leaves, are skipped.
  local identity fields enable_personal=false
  local -a identities=() enterprise_identities=()
  fields="$(dybatpho::split "${IDENTITIES:-}" ",")"
  mapfile -t identities <<< "${fields}"
  for identity in "${identities[@]}"; do
    identity="$(dybatpho::trim "${identity}")"
    if dybatpho::string_is_blank "${identity}"; then
      continue
    fi
    # chezmoi splits a multichoice answer on `/` and the flag itself on `,`
    # and `=`, so only a plain code can be passed through.
    [[ "${identity}" =~ ^[A-Za-z0-9_-]+$ ]] || dybatpho::die "Invalid identity: ${identity}"
    if [[ "${identity}" == "personal" ]]; then
      enable_personal=true
    else
      enterprise_identities+=("${identity}")
    fi
  done
  if [[ "${enable_personal}" == true ]]; then
    CHEZMOI_INIT_ARGS+=(--promptBool "${PROMPT_PERSONAL}=true")
  fi
  if ((${#enterprise_identities[@]} > 0)); then
    local companies
    companies="$(dybatpho::array_join enterprise_identities "/")"
    CHEZMOI_INIT_ARGS+=(--promptMultichoice "${PROMPT_ENTERPRISE}=${companies}")
  fi
}

#######################################
# @description Fit git and the proxy to the network for the next applies: the
# git rewrites land where `git/config` includes them, before the submodules
# are cloned, and the proxy is exported only when this network reaches it.
# The proxy is a secret of the machine, so dynet's config can only be applied
# once the secrets submodule and the age identities are in place, after
# `~/.ssh`.
# @noargs
#######################################
function _detect_network {
  chezmoi apply "${HOME}/.config/dynet" "${HOME}/.config/git/config"
  # shellcheck source=lib/network.sh
  . "${SCRIPT_DIR}/lib/network.sh"
  network::detect "${HOME}/.config/dynet/config.json" "${HOME}/.local/state/dynet"
}

#######################################
# @description Install every tool this script needs before it can run chezmoi
# @env BIN_DIR Directory to install binary
# @noargs
#######################################
# dyshellint disable=SC2310 the predicates of this script are meant to be tested here
function _install_prerequisites {
  dybatpho::require "git"
  dybatpho::require "curl"
  if ! _chezmoi_is_recent; then
    # Installed ahead of PATH, so it shadows an older chezmoi of the system.
    _install_chezmoi
    _chezmoi_is_recent || dybatpho::die "Failed to install a chezmoi recent enough for .chezmoiversion"
  fi
  if ! dybatpho::is command "age"; then
    _install_age
    dybatpho::is command "age" || dybatpho::die "Failed to install age"
  fi
  if ! dybatpho::is command "yq"; then
    _install_yq
    dybatpho::is command "yq" || dybatpho::die "Failed to install yq"
  fi
}

#######################################
# @description Apply the root-owned operating system layer. It is skipped
# inside a container, whose system files belong to the image or the runtime,
# unless `--system` asks for it, and without root or a way to get it.
# @env SYSTEM_LAYER Whether to apply it even inside a container
# @env BIN_DIR Directory where `scz` is installed
# @noargs
#######################################
# dyshellint disable=SC2310 the predicates of this script are meant to be tested here
function _apply_system_layer {
  if _is_container && ! dybatpho::is true "${SYSTEM_LAYER:-false}"; then
    dybatpho::info "Inside a container: skipping the system layer, pass --system to apply it"
    return 0
  fi
  # The escalation is held for the whole run of the layer.
  if ! dybatpho::is_root && ! { dybatpho::privilege_needed && dybatpho::privilege_acquire; }; then
    dybatpho::info "No root access: skipping the system layer"
    return 0
  fi
  local os scz
  os="$(dybatpho::goos)"
  scz="$(dybatpho::path_join "${BIN_DIR}" "scz")"
  case "${os}" in
    darwin)
      dybatpho::header "Setup operating system"
      "${scz}" apply /Applications
      "${scz}" apply /private
      ;;
    linux)
      dybatpho::header "Setup operating system"
      "${scz}" apply
      ;;
    *) dybatpho::debug "No operating system layer for ${os}" ;;
  esac
}

#######################################
# @description Main function
# @noargs
#######################################
function _main {
  _install_prerequisites

  dybatpho::header "Initialize chezmoi"
  _chezmoi_init_args
  chezmoi "${CHEZMOI_INIT_ARGS[@]}"

  # Apply configuration by order
  local -a params=()
  if dybatpho::compare_log_level trace; then
    params=("--debug")
  fi
  dybatpho::header "Setup Git modules"
  chezmoi apply \
    "${ROOT_DIR}/.gitmodules" \
    --destination "${ROOT_DIR}" \
    --source "${ROOT_DIR}/cascadeur" \
    --mode file "${params[@]}"
  dybatpho::header "Setup SSH"
  chezmoi apply "${HOME}/.ssh" "${params[@]}"
  _detect_network
  dybatpho::header "Setup other dotfiles"
  chezmoi apply "${params[@]}"

  # Not on Termux, which has no system layer.
  _apply_system_layer

  dybatpho::success "Setup complete"
}

# Sourced, as by its tests, it only defines the functions above.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  dybatpho::generate_from_spec _spec_main "$@"
fi
