#!/usr/bin/env bash
# @file docker.sh
# @brief Build a toolbox container image for one identity
# @description The images differ only in registry name, identity, base
#   distribution and which secrets they carry; everything else is shared.
SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE=""
DOCKERFILE=""
BUILD_ARGS=()
SECRETS=()

#######################################
# @description Spec of docker.sh
#######################################
# shellcheck disable=SC2154
function _spec_main {
  dybatpho::opts::setup "Build a toolbox container image" MAIN_ARGS action:"_main"
  dybatpho::opts::param "Log level" LOG_LEVEL --log-level -l init:="info" validate:"dybatpho::validate_log_level \$OPTARG"
  dybatpho::opts::disp "Show help" --help -h action:"dybatpho::generate_help _spec_main"
}

#######################################
# @description Update git submodules for running this script only
#######################################
function _update_git_modules {
  if [[ ! -f "$SCRIPT_DIR/lib/dybatpho/init.sh" ]]; then
    git -C "$REPO_DIR" submodule update --init "$SCRIPT_DIR/lib/dybatpho"
  fi
}

#######################################
# @description Read the age passphrase of an identity from the password
#   manager and export it for the build, masked in any log it reaches
# @arg $1 string Identity name, used as both the key and the rbw field
# @env AGE_PASSPHRASES Exported for the age_passphrases build secret
#######################################
function _export_age_passphrase {
  local identity passphrase
  dybatpho::expect_args identity -- "$@"
  dybatpho::require "rbw"
  if [[ "$identity" == "personal" ]]; then
    passphrase="$(rbw get 'Age Dotfiles')"
  else
    passphrase="$(rbw get 'Age Dotfiles' --field "$identity")"
  fi
  dybatpho::secret_register "$passphrase"
  export AGE_PASSPHRASES="${identity}=${passphrase}"
  SECRETS+=(--secret "id=age_passphrases,env=AGE_PASSPHRASES")
}

#######################################
# @description Configure the public image, which carries no secret at all
#######################################
function _configure_public {
  IMAGE="dynamotn/toolbox"
  DOCKERFILE="$(dybatpho::path_join "$REPO_DIR" "docker" "Dockerfile.alpine")"
  export TOOLBOX_TYPE=""
}

#######################################
# @description Configure the Alpine personal image
#######################################
function _configure_personal {
  IMAGE="git.dynamotn.dev/config/dotfiles"
  DOCKERFILE="$(dybatpho::path_join "$REPO_DIR" "docker" "Dockerfile.alpine")"
  export TOOLBOX_TYPE="personal"
  BUILD_ARGS+=(--build-arg IDENTITIES="personal")
  _export_age_passphrase "personal"
}

#######################################
# @description Configure the Arch personal image
#######################################
function _configure_personal_arch {
  IMAGE="git.dynamotn.dev/config/dotfiles:arch"
  DOCKERFILE="$(dybatpho::path_join "$REPO_DIR" "docker" "Dockerfile.arch")"
  export TOOLBOX_TYPE="personal"
  _export_age_passphrase "personal"
}

#######################################
# @description Configure an enterprise image, which also needs the SSL
#   certificate only its own age identity can open
# @arg $1 string Enterprise code, such as `F1`
#######################################
function _configure_enterprise {
  local enterprise key certificate
  dybatpho::expect_args enterprise -- "$@"
  dybatpho::require "age"
  IMAGE="git.example.com/dynamo/toolbox:${enterprise}"
  DOCKERFILE="$(dybatpho::path_join "$REPO_DIR" "docker" "Dockerfile.alpine")"
  export TOOLBOX_TYPE="$enterprise"
  _export_age_passphrase "$enterprise"

  key="$(dybatpho::path_join "$HOME" ".config" "chezmoi" "enterprise-${enterprise}.key")"
  dybatpho::is file "$key" || dybatpho::die "No age identity at $key"
  certificate="$(
    age -d -i "$key" \
      "$(dybatpho::path_join "$REPO_DIR" "secrets" "data" "enterprise-${enterprise}" "ssl.crt.age")"
  )"
  dybatpho::secret_register "$certificate"
  export SSL_CERT="$certificate"
  SECRETS+=(--secret "id=ssl_cert,env=SSL_CERT")
}

#######################################
# @description Main function
# @env MAIN_ARGS Positional arguments; the first names the image to build
#######################################
function _main {
  local target bin_dir
  ((${#MAIN_ARGS[@]} > 0)) \
    || dybatpho::die "Specify an image: public, personal, personal-arch, or enterprise-<CODE>"
  target="${MAIN_ARGS[0]}"

  dybatpho::require "docker"
  dybatpho::require "gomplate"
  SECRETS=(--secret "id=github_token,env=GITHUB_TOKEN")

  case "$target" in
    public) _configure_public ;;
    personal) _configure_personal ;;
    personal-arch) _configure_personal_arch ;;
    enterprise-*) _configure_enterprise "${target#enterprise-}" ;;
    *) dybatpho::die "Unknown image $target" ;;
  esac

  # A quoted "~" never expands, which is why the tasks this replaces silently
  # ran without ~/.local/bin on PATH.
  bin_dir="$(dybatpho::path_join "$HOME" ".local" "bin")"
  export PATH="$bin_dir:$PATH"

  dybatpho::header "Rendering .dockerignore"
  gomplate -f "$(dybatpho::path_join "$REPO_DIR" ".dockerignore.tmpl")" \
    -o "$(dybatpho::path_join "$REPO_DIR" ".dockerignore")"

  dybatpho::header "Building $IMAGE"
  docker build --network=host \
    "${SECRETS[@]}" \
    "${BUILD_ARGS[@]}" \
    --no-cache \
    -f "$DOCKERFILE" \
    -t "$IMAGE" "$REPO_DIR"
  dybatpho::success "Built $IMAGE"
}

_update_git_modules

# shellcheck source=lib/dybatpho/init.sh
. "$SCRIPT_DIR/lib/dybatpho/init.sh" --modules cli
dybatpho::register_common_handlers
dybatpho::generate_from_spec _spec_main "$@"
