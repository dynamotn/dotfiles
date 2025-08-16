#!/usr/bin/env bash
SETUP_DIR=$(dirname "$(readlink -f "$0")")
BIN_DIR="$HOME/.local/bin"

# Update necessary submodules
cd "$SETUP_DIR" || exit
git submodule update --init --remote "$SETUP_DIR"/lib/dybatpho "$SETUP_DIR"/lib/expect-age

# shellcheck source=lib/dybatpho/init.sh
. "$SETUP_DIR/lib/dybatpho/init.sh"
dybatpho::register_common_handlers

function _spec_main {
  dybatpho::opts::setup "Setup your machine from dotfiles" MAIN_ARGS action:"_main"
  dybatpho::opts::param "Log level" LOG_LEVEL --log-level -l init:="info" validate:"dybatpho::validate_log_level \$OPTARG"
  dybatpho::opts::param "Use default values of chezmoi" USE_DEFAULT --use-default -d optional:true
  dybatpho::opts::disp "Show help" --help -h action:"dybatpho::generate_help _spec_main"
}

_install_chezmoi() {
  if [ ! "$(command -v chezmoi)" ]; then
    dybatpho::header "Install chezmoi"
    if command -v termux-setup-storage &> /dev/null; then
      pkg install -y chezmoi
      return
    fi

    if [ "$(command -v curl)" ]; then
      sh -c "$(curl -fsSL https://git.io/chezmoi)" -- -b "$BIN_DIR"
    elif [ "$(command -v wget)" ]; then
      sh -c "$(wget -qO- https://git.io/chezmoi)" -- -b "$BIN_DIR"
    else
      _error "To install chezmoi, you must have curl or wget installed."
    fi
  fi
}

_install_age() {
  if [ ! "$(command -v age)" ]; then
    dybatpho::header "Install age"
    if command -v termux-setup-storage &> /dev/null; then
      pkg install -y age
      return
    fi

    temp=$(mktemp)
    if [ "$(command -v curl)" ]; then
      curl -sSL -o "$temp" https://dl.filippo.io/age/latest?for=linux/amd64
    elif [ "$(command -v wget)" ]; then
      wget -qO "$temp" https://dl.filippo.io/age/latest?for=linux/amd64
    else
      _error "To install age, you must have curl or wget installed."
    fi

    if [ "$(command -v tar)" ]; then
      tar -C "$BIN_DIR" -xzf "$temp" --strip=1 age/age
    else
      _error "To install age, you must have tar and gzip installed."
    fi
    rm -rf "$temp"
  fi
}

_main() {
  # Install chezmoi and age
  mkdir -p "$BIN_DIR"
  export PATH="$BIN_DIR":"$PATH"
  _install_chezmoi

  # Modify source directory of chezmoi, manipulate chezmoi config and generate
  # to chezmoi's default config template
  dybatpho::header "Initialize chezmoi"
  echo "sourceDir: \"$(readlink -f "$SETUP_DIR"/..)\"" > "$SETUP_DIR"/../home/.chezmoi.yaml.tmpl
  cat "$SETUP_DIR"/../.chezmoi.yaml.tmpl >> "$SETUP_DIR"/../home/.chezmoi.yaml.tmpl
  mkdir -p "$HOME/.config/chezmoi/hooks/diff" && touch "$HOME/.config/chezmoi/hooks/diff/pre.sh"
  dybatpho::header "Please answer the following questions"
  # shellcheck disable=SC2086
  if [ "$USE_DEFAULT" = "true" ]; then
    prompt="--promptDefaults"
  else
    prompt="--prompt"
  fi
  chezmoi init -S "$SETUP_DIR/.." "$prompt"

  # Apply configuration by order
  dybatpho::header "Setup SSH"
  _install_age
  # shellcheck disable=SC2086
  if dybatpho::compare_log_level debug; then
    chezmoi apply --debug "$HOME"/.ssh
  else
    chezmoi apply "$HOME"/.ssh
  fi
  dybatpho::header "Setup other dotfiles"
  # shellcheck disable=SC2086
  if dybatpho::compare_log_level debug; then
    chezmoi apply --debug
  else
    chezmoi apply
  fi

  if
    ! command -v termux-setup-storage &> /dev/null
    and ! command -v sw_vers &> /dev/null
  then
    dybatpho::header "Setup operating system"
    ~/.local/bin/scz apply
  fi

  # Modify remote url of dotfiles
  dybatpho::header "Setup remote url of dotfiles"
  cd "$SETUP_DIR/.." || exit
  git remote set-url origin git@gitlab.com:dynamo-config/dotfiles
  git remote add gh git@github.com:dynamotn/dotfiles.git || git remote set-url gh git@github.com:dynamotn/dotfiles.git
  git config --local include.path ../.gitconfig

  dybatpho::success "Setup complete"
}

dybatpho::generate_from_spec _spec_main "$@"
