#!/usr/bin/env bash
# @file setup.sh
# @brief Setup your machine from dotfiles
SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
BIN_DIR="$HOME/.local/bin"

#######################################
# @description Spec of setup.sh
#######################################
# shellcheck disable=SC2154
function _spec_main {
  dybatpho::opts::setup "Setup your machine from dotfiles" MAIN_ARGS action:"_main"
  dybatpho::opts::param "Log level" LOG_LEVEL --log-level -l init:="info" validate:"dybatpho::validate_log_level \$OPTARG"
  dybatpho::opts::flag "Use default values of chezmoi" USE_DEFAULT --use-default -d on:true off:false init:="false"
  dybatpho::opts::param "List of identities to decrypt, separated by \`,\`" IDENTITIES --identities -i optional:true on:
  dybatpho::opts::disp "Show help" --help -h action:"dybatpho::generate_help _spec_main"
}

#######################################
# @description Update git submodules for running this script only
#######################################
function _update_git_modules {
  if [[ ! -f "$SCRIPT_DIR/lib/dybatpho/init.sh" ]]; then
    git -C "$SCRIPT_DIR/.." submodule update --init "$SCRIPT_DIR/lib/dybatpho"
  fi
}

#######################################
# @description In-place sed compatible with both GNU and BSD sed
#######################################
function _sed_i {
  if sed --version 2>&1 | grep -q GNU; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

#######################################
# @description Install binary version of chezmoi
# @env BIN_DIR Directory to install binary
#######################################
function _install_chezmoi {
  dybatpho::info "Installing chezmoi to $BIN_DIR"
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$BIN_DIR"
}

#######################################
# @description Install binary version of age
# @env BIN_DIR Directory to install binary
#######################################
function _install_age {
  dybatpho::info "Installing age to $BIN_DIR"
  dybatpho::require "tar"
  dybatpho::create_temp "temp" ".tar.gz"
  # shellcheck disable=SC2154
  dybatpho::curl_download "https://dl.filippo.io/age/latest?for=$(dybatpho::goos)/$(dybatpho::goarch)" "$temp"
  dybatpho::archive_extract "$temp" "$BIN_DIR" 1
}

#######################################
# @description Install binary version of yq
# @env BIN_DIR Directory to install binary
#######################################
function _install_yq {
  dybatpho::info "Installing yq to $BIN_DIR"
  local yq_path
  yq_path=$(dybatpho::path_join "$BIN_DIR" "yq")
  # shellcheck disable=SC2154
  dybatpho::curl_download "https://github.com/mikefarah/yq/releases/latest/download/yq_$(dybatpho::goos)_$(dybatpho::goarch)" "$yq_path"
  chmod +x "$yq_path"
}

#######################################
# @description Generate chezmoi config file from template
# @env IDENTITIES Comma separated list of identities to decrypt
#######################################
function _generate_chezmoi_config {
  local root_dir origin_config dest_config
  root_dir="$(dybatpho::path_normalize "$(dybatpho::path_join "$SCRIPT_DIR" "..")")"
  origin_config="$(dybatpho::path_join "$root_dir" ".chezmoi.yaml.tmpl")"
  dest_config="$(dybatpho::path_join "$root_dir" "home" ".chezmoi.yaml.tmpl")"

  # Put current chezmoi source directory
  echo "sourceDir: \"${root_dir}\"" > "$dest_config"
  # Put rest of config from origin template
  command cat "$origin_config" >> "$dest_config"

  # Generate decrypt config
  local enable_personal=false
  local identities=()
  local raw_identities="${IDENTITIES:-}"
  IFS=',' read -r -a identities <<< "$raw_identities"
  local enterprise_identities=()
  for identity in "${identities[@]}"; do
    identity="$(dybatpho::trim "${identity}")"
    if dybatpho::string_is_blank "${identity}"; then
      continue
    fi
    if [[ "${identity}" == "personal" ]]; then
      enable_personal=true
    else
      enterprise_identities+=("$identity")
    fi
  done
  if [[ "${enable_personal}" == true ]]; then
    _sed_i 's#decryptPersonal: .*#decryptPersonal: true#g' "$dest_config"
    _sed_i "s#\(\$decryptPersonal := .*\) false }}#\1 true }}#g" "$dest_config"
  fi
  if dybatpho::array_first enterprise_identities > /dev/null 2>&1; then
    _sed_i "s#\(\$decryptEnterprise := .*\) false }}#\1 true }}#g" "$dest_config"
    _sed_i "s#\$company := \(.*\) }}#\$company := \"\" }}#g" "$dest_config"
    for identity in "${enterprise_identities[@]}"; do
      _sed_i "s#\(\$listDecryptEnterprise := .*\) }}#\1 \"${identity}\" }}#g" "$dest_config"
    done
  fi
}

#######################################
# @description Main function
#######################################
function _main {
  dybatpho::header "Initialize chezmoi"
  _generate_chezmoi_config

  # Initialize chezmoi config from user input
  dybatpho::info "Please answer the following questions"
  local prompt="--prompt"
  # shellcheck disable=SC2086
  if [[ "$USE_DEFAULT" == "true" ]]; then
    prompt="--promptDefaults"
  fi
  chezmoi init -S "$SCRIPT_DIR/.." "$prompt"

  # Apply configuration by order
  local params=()
  # shellcheck disable=SC2086
  if dybatpho::compare_log_level trace; then
    params=("--debug")
  fi
  dybatpho::header "Setup Git modules"
  chezmoi apply \
    "$SCRIPT_DIR/../.gitmodules" \
    --destination "$SCRIPT_DIR/.." \
    --source "$SCRIPT_DIR/../cascadeur" \
    --mode file "${params[@]}"
  dybatpho::header "Setup SSH"
  chezmoi apply "${HOME}/.ssh" "${params[@]}"
  local proxy
  proxy="$(chezmoi data | yq .httpProxy 2>/dev/null || true)"
  [[ "${proxy}" == "null" ]] && proxy=""
  if ! dybatpho::string_is_blank "$proxy"; then
    export https_proxy="$proxy"
    export http_proxy="$proxy"
    local addresses=()
    readarray -t addresses < <(chezmoi data 2>/dev/null | yq e -o=j -I=0 -r '.noProxyAddresses[] // empty' 2>/dev/null || true)
    if ((${#addresses[@]} > 0)); then
      local no_proxy_val
      no_proxy_val="$(dybatpho::array_join "addresses" ",")"
      export no_proxy="$no_proxy_val"
    fi
  fi
  dybatpho::header "Setup other dotfiles"
  chezmoi apply "${params[@]}"

  # Apply OS specific configuration if not Termux
  if sudo -n true 2> /dev/null || sudo true &> /dev/null; then
    case "$(dybatpho::goos)" in
      darwin)
        dybatpho::header "Setup operating system"
        "$(dybatpho::path_join "$BIN_DIR" "scz")" apply /Applications
        "$(dybatpho::path_join "$BIN_DIR" "scz")" apply /private
        ;;
      linux)
        dybatpho::header "Setup operating system"
        "$(dybatpho::path_join "$BIN_DIR" "scz")" apply
        ;;
    esac
  fi

  dybatpho::success "Setup complete"
}

_update_git_modules

# shellcheck source=lib/dybatpho/init.sh
. "$SCRIPT_DIR/lib/dybatpho/init.sh"
BIN_DIR="$(dybatpho::path_join "$HOME" ".local" "bin")"
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR":"$PATH"
dybatpho::register_common_handlers
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

dybatpho::generate_from_spec _spec_main "$@"
