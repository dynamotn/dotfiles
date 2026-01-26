#!/usr/bin/env bash
# @file setup.sh
# @brief Setup your machine from dotfiles
SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
BIN_DIR="$HOME/.local/bin"

#######################################
# @description Spec of setup.sh
#######################################
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
  if [ ! -f "$SCRIPT_DIR/lib/dybatpho/init.sh" ]; then
    cd "$SCRIPT_DIR" || exit
    git submodule update --init --remote "$SCRIPT_DIR/lib/dybatpho" "$SCRIPT_DIR/lib/expect-age"
  fi
}

#######################################
# @description Install binary version of chezmoi
# @env BIN_DIR Directory to install binary
#######################################
function _install_chezmoi {
  bash -c "$(curl -fsSL https://git.io/chezmoi)" -- -b "$BIN_DIR"
}

#######################################
# @description Install binary version of age
# @env BIN_DIR Directory to install binary
#######################################
function _install_age {
  dybatpho::require "tar"
  dybatpho::create_temp "temp" "tar.gz"
  # shellcheck disable=SC2154
  dybatpho::curl_download "https://dl.filippo.io/age/latest?for=$(dybatpho::goos)/$(dybatpho::goarch)" "$temp"
  tar -C "$BIN_DIR" -xzf "$temp" --strip=1 age/age
}

#######################################
# @description Install binary version of yq
# @env BIN_DIR Directory to install binary
#######################################
function _install_yq {
  # shellcheck disable=SC2154
  dybatpho::curl_download "https://github.com/mikefarah/yq/releases/latest/download/yq_$(dybatpho::goos)_$(dybatpho::goarch)" "$BIN_DIR/yq"
  chmod +x "$BIN_DIR/yq"
}

#######################################
# @description Generate chezmoi config file from template
# @env IDENTITIES Comma separated list of identities to decrypt
#######################################
function _generate_chezmoi_config {
  local origin_config="$SCRIPT_DIR/../.chezmoi.yaml.tmpl"
  local dest_config="$SCRIPT_DIR/../home/.chezmoi.yaml.tmpl"

  # Put current chezmoi source directory
  echo "sourceDir: \"$(readlink -f "$SCRIPT_DIR/..")\"" > "$dest_config"
  # Put rest of config from origin template
  command cat "$origin_config" >> "$dest_config"

  # Generate decrypt config
  # shellcheck disable=SC2153
  if [[ "$IDENTITIES" =~ /*personal*/ ]]; then
    sed -i 's#decryptPersonal: .*#decryptPersonal: true#g' "$dest_config"
    sed -i "s#\(\$decryptPersonal := .*\) false }}#\1 true }}#g" "$dest_config"
  fi
  local identities=()
  IFS=',' read -r -a identities <<< "$IDENTITIES"
  local enterprise_identities=()
  for identity in "${identities[@]}"; do
    if [ -n "$identity" ] && [ "$identity" != "personal" ]; then
      enterprise_identities+=("$identity")
    fi
  done
  sed -i "s#\(\$decryptEnterprise := .*\) false }}#\1 true }}#g" "$dest_config"
  sed -i "s#\$company := \(.*\) }}#\$company := \"\" }}#g" "$dest_config"
  for identity in "${enterprise_identities[@]}"; do
    sed -i "s#\(\$listDecryptEnterprise := .*\) }}#\1 \"${identity}\" }}#g" "$dest_config"
  done
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
  if [ "$USE_DEFAULT" = "true" ]; then
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
  # shellcheck disable=SC2155
  local proxy="$(chezmoi data | yq .httpProxy)"
  if ! dybatpho::is empty "$proxy"; then
    export https_proxy="$proxy"
    export http_proxy="$proxy"
    # shellcheck disable=SC2034
    readarray addresses < <(chezmoi data | yq e -o=j -I=0 -r '.noProxyAddresses[]')
    # shellcheck disable=SC2155
    export no_proxy="$(dybatpho::array_join "addresses" ",")"
  fi
  dybatpho::header "Setup RBW"
  if [ "$(chezmoi data | yq .decryptPersonal)" == "true" ]; then
    chezmoi apply "${HOME}/.config/rbw" "${params[@]}"
  fi
  readarray identities < <(chezmoi data | yq e -o=j -I=0 -r '.decryptEnterprise[]')
  for identity in "${identities[@]}"; do
    if dybatpho::is dir "$SCRIPT_DIR/../home/dot_config/rbw-enterprise-$(dybatpho::lower "$identity")"; then
      chezmoi apply "${HOME}/.config/rbw-enterprise-$(dybatpho::lower "$identity")" "${params[@]}"
    fi
  done
  dybatpho::header "Setup other dotfiles"
  chezmoi apply "${params[@]}"

  # Apply OS specific configuration if not Termux
  case "$(dybatpho::goos)" in
    darwin)
      dybatpho::header "Setup operating system"
      ~/.local/bin/scz apply /Applications
      ~/.local/bin/scz apply /private
      ;;
    linux)
      dybatpho::header "Setup operating system"
      ~/.local/bin/scz apply
      ;;
  esac

  dybatpho::success "Setup complete"
}

mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR":"$PATH"
_update_git_modules

# shellcheck source=lib/dybatpho/init.sh
. "$SCRIPT_DIR/lib/dybatpho/init.sh"
dybatpho::register_common_handlers
dybatpho::require "git"
dybatpho::require "curl"
# shellcheck disable=2091
while ! $(dybatpho::require "chezmoi"); do
  _install_chezmoi
done
# shellcheck disable=2091
while ! $(dybatpho::require "age"); do
  _install_age
done
# shellcheck disable=2091
while ! $(dybatpho::require "yq"); do
  _install_yq
done

dybatpho::generate_from_spec _spec_main "$@"
