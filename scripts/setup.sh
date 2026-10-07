#!/usr/bin/env bash
# @file setup.sh
# @brief Setup your machine from dotfiles
# @description Bring a fresh machine up to this repository: fetch the dybatpho
# submodule, install the tools chezmoi itself needs, generate the chezmoi
# configuration from its template and apply the dotfiles in order.
SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
# The library lives in a submodule, which a fresh clone or a new worktree
# does not populate. Fetch it before sourcing, or nothing below is defined.
if [[ ! -f "${SCRIPT_DIR}/lib/dybatpho/init.sh" ]]; then
  git -C "${SCRIPT_DIR}/.." submodule update --init "${SCRIPT_DIR}/lib/dybatpho"
fi
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/dybatpho/init.sh
. "${SCRIPT_DIR}/lib/dybatpho/init.sh" --modules cli network archive array privilege
dybatpho::register_common_handlers
BIN_DIR="$(dybatpho::path_join "${HOME}" ".local" "bin")"
BIN_DIR="$(dybatpho::ensure_dir "${BIN_DIR}")"
export PATH="${BIN_DIR}:${PATH}"

#######################################
# @description Spec of setup.sh
# @noargs
#######################################
# shellcheck disable=SC2154
function _spec_main {
  dybatpho::opts::setup "Setup your machine from dotfiles" MAIN_ARGS action:"_main"
  dybatpho::opts::param "Log level" LOG_LEVEL --log-level -l init:="info" \
    validate:"dybatpho::validate_log_level \$OPTARG"
  dybatpho::opts::flag "Use default values of chezmoi" USE_DEFAULT --use-default -d on:true off:false init:="false"
  dybatpho::opts::param "List of identities to decrypt, separated by \`,\`" IDENTITIES --identities -i optional:true on:
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
# @description Generate chezmoi config file from template
# @env IDENTITIES Comma separated list of identities to decrypt
# @noargs
#######################################
# The replacement patterns are Go template text of the chezmoi config, so the
# `$name` in them is not a shell expansion and must stay single quoted.
# shellcheck disable=SC2016
function _generate_chezmoi_config {
  local root_dir origin_config dest_config
  root_dir="$(dybatpho::path_join "${SCRIPT_DIR}" "..")"
  root_dir="$(dybatpho::path_normalize "${root_dir}")"
  origin_config="$(dybatpho::path_join "${root_dir}" ".chezmoi.yaml.tmpl")"
  dest_config="$(dybatpho::path_join "${root_dir}" "home" ".chezmoi.yaml.tmpl")"

  # Put current chezmoi source directory
  printf 'sourceDir: "%s"\n' "${root_dir}" > "${dest_config}"
  # Put rest of config from origin template
  command cat "${origin_config}" >> "${dest_config}"

  # Generate decrypt config. Blank fields, such as the one a trailing `,`
  # leaves, are skipped below.
  local enable_personal=false identity fields
  local -a identities=()
  fields="$(dybatpho::split "${IDENTITIES:-}" ",")"
  mapfile -t identities <<< "${fields}"
  local -a enterprise_identities=()
  for identity in "${identities[@]}"; do
    identity="$(dybatpho::trim "${identity}")"
    if dybatpho::string_is_blank "${identity}"; then
      continue
    fi
    if [[ "${identity}" == "personal" ]]; then
      enable_personal=true
    else
      enterprise_identities+=("${identity}")
    fi
  done
  if [[ "${enable_personal}" == true ]]; then
    dybatpho::file_replace "${dest_config}" 'decryptPersonal: .*' 'decryptPersonal: true'
    dybatpho::file_replace "${dest_config}" '\(\$decryptPersonal := .*\) false }}' '\1 true }}'
  fi
  if dybatpho::array_first enterprise_identities > /dev/null 2>&1; then
    dybatpho::file_replace "${dest_config}" '\(\$decryptEnterprise := .*\) false }}' '\1 true }}'
    dybatpho::file_replace "${dest_config}" '$company := \(.*\) }}' '$company := "" }}'
    for identity in "${enterprise_identities[@]}"; do
      dybatpho::file_replace "${dest_config}" '\(\$listDecryptEnterprise := .*\) }}' "\\1 \"${identity}\" }}"
    done
  fi
}

#######################################
# @description Install every tool this script needs before it can run chezmoi
# @env BIN_DIR Directory to install binary
# @noargs
#######################################
function _install_prerequisites {
  dybatpho::require "git"
  dybatpho::require "curl"
  if ! dybatpho::is command "chezmoi"; then
    _install_chezmoi
    dybatpho::is command "chezmoi" || dybatpho::die "Failed to install chezmoi"
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
# @description Main function
# @noargs
#######################################
# dyshellint disable=SC2154 USE_DEFAULT is assigned by dybatpho::opts from _spec_main
function _main {
  _install_prerequisites

  dybatpho::header "Initialize chezmoi"
  _generate_chezmoi_config

  # Initialize chezmoi config from user input
  dybatpho::info "Please answer the following questions"
  local prompt="--prompt"
  if [[ "${USE_DEFAULT}" == "true" ]]; then
    prompt="--promptDefaults"
  fi
  chezmoi init -S "${SCRIPT_DIR}/.." "${prompt}"

  # Apply configuration by order
  local -a params=()
  if dybatpho::compare_log_level trace; then
    params=("--debug")
  fi
  dybatpho::header "Setup Git modules"
  chezmoi apply \
    "${SCRIPT_DIR}/../.gitmodules" \
    --destination "${SCRIPT_DIR}/.." \
    --source "${SCRIPT_DIR}/../cascadeur" \
    --mode file "${params[@]}"
  dybatpho::header "Setup SSH"
  chezmoi apply "${HOME}/.ssh" "${params[@]}"
  local proxy
  proxy="$(chezmoi data | yq .httpProxy 2> /dev/null || true)"
  [[ "${proxy}" == "null" ]] && proxy=""
  if ! dybatpho::string_is_blank "${proxy}"; then
    export https_proxy="${proxy}"
    export http_proxy="${proxy}"
    local -a addresses=()
    readarray -t addresses < <(
      chezmoi data 2> /dev/null \
        | yq e -o=j -I=0 -r '.noProxyAddresses[] // empty' 2> /dev/null \
        || true
    )
    if ((${#addresses[@]} > 0)); then
      local no_proxy_val
      no_proxy_val="$(dybatpho::array_join "addresses" ",")"
      export no_proxy="${no_proxy_val}"
    fi
  fi
  dybatpho::header "Setup other dotfiles"
  chezmoi apply "${params[@]}"

  # Apply OS specific configuration if not Termux. The OS layer is root-owned,
  # so it is skipped without root, and the escalation is held for its run.
  if dybatpho::is_root || { dybatpho::privilege_needed && dybatpho::privilege_acquire; }; then
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
  fi

  dybatpho::success "Setup complete"
}

dybatpho::generate_from_spec _spec_main "$@"
