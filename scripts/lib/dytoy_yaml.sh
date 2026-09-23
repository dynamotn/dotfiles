#!/usr/bin/env bash
# shellcheck disable=2154,2155
# @file dytoy_yaml.sh
# @brief Library `dytoy` to read the tools YAML file and install what it describes
# @description Library `dytoy` to read the tools YAML file and install what it
# describes. Queries go through the `json` module of dybatpho instead of calling
# `yq` by hand, and every distro installer shares `dytoy::install_package`.
dybatpho::load json

#######################################
# @description Print the path of the tools YAML file
# @noargs
#######################################
function dytoy::yaml_file {
  dybatpho::path_join "$(dybatpho::xdg_config_dir dytoy)" "tools.yaml"
}

#######################################
# @description Get a field of a YAML content of a tool
# @arg $1 string YAML content
# @arg $2 string Field to extract, as a `yq` expression without the leading dot
#######################################
function dytoy::get_field {
  local yaml field
  dybatpho::expect_args yaml field -- "$@"
  dybatpho::json_get "$yaml" ".${field}"
}

#######################################
# @description Get YAML content for a specific tool
# @arg $1 string Name of tool
# @arg $2 string Field to extract from the YAML file, `all` to get all fields
# @arg $3 string Method to filter by, only used when field is `all`
#######################################
function dytoy::get_yaml {
  local name field
  dybatpho::expect_args name field -- "$@"
  local filter
  # Only a scalar field is read raw: the others stay JSON so a caller can pipe
  # them back through `yq`.
  local -a options=(-o=j -I=0)
  case $field in
    all)
      local method="${3:-}"
      filter="filter(.name == \"${name}\" and .method == \"${method}\") | explode ."
      ;;
    archive | *.packages | *.services)
      filter="filter(.name == \"${name}\") | explode . | .[].${field}.[]"
      ;;
    dependencies)
      filter="filter(.name == \"${name}\") | explode . | .[].${field}.[]"
      options+=(-r)
      ;;
    *)
      filter="filter(.name == \"${name}\") | explode . | .[].${field}"
      options+=(-r)
      ;;
  esac
  dybatpho::yaml_query "$(dytoy::yaml_file)" "$filter" "${options[@]}"
}

#######################################
# @description Install dependencies from the YAML file
# @arg $1 string Name of tool
#######################################
function dytoy::install_dependencies {
  local name
  dybatpho::expect_args name -- "$@"
  readarray -t dependencies < <(dytoy::get_yaml "$name" "dependencies")
  for dependency in "${dependencies[@]}"; do
    dybatpho::debug "Need dependency: $dependency"
    local method
    method=$(dytoy::get_yaml "$dependency" "method")
    dybatpho::dry_run "$(dybatpho::path_join "$HOME" ".local" "bin" "dytoy_${method}")" -i -t "$dependency"
  done
}

#######################################
# @description Run a script, or show what it contains in dry run mode
# @arg $1 string Script file path
# @env DRY_RUN boolean If true, show the script file instead of running it
#######################################
function dytoy::run_script {
  local script_file
  dybatpho::expect_args script_file -- "$@"
  # A tool without a hook still gets a temp file, and reporting an empty script
  # as something about to run says nothing.
  if ! dybatpho::is file "$script_file"; then
    dybatpho::debug "No script at $script_file, skipping"
    return 0
  fi
  local content
  content="$(< "$script_file")"
  if dybatpho::string_is_blank "$content"; then
    dybatpho::debug "Nothing to run in $script_file, skipping"
    return 0
  fi
  if dybatpho::is true "$DRY_RUN"; then
    # The contents go to stderr, so the header goes with them rather than to
    # stdout where the two would be separated.
    dybatpho::info "RUN: $script_file"
    dybatpho::show_file "$script_file"
  else
    # shellcheck disable=1090
    . "$script_file"
  fi
  echo > "${script_file}" # Clear the script file after running
}

#######################################
# @description Create a script file with the given content to install a tool
# @arg $1 string Name of the tool
# @arg $2 string Path of the script file to create
# @arg $3 string Content of the script
# @arg $4 string Kind of script (e.g., shell, before-install hook, after-install hook)
#######################################
function dytoy::create_script {
  local name path content kind
  dybatpho::expect_args name path content kind -- "$@"
  if [[ "$content" == "null" ]] || dybatpho::string_is_blank "$content"; then
    return 0
  fi

  local lib_dir
  lib_dir="$(dybatpho::path_dirname "${BASH_SOURCE[0]}")"
  cat << EOF > "${path}"
. $(dybatpho::path_join "$lib_dir" "dybatpho" "init.sh") --modules network
dybatpho::register_common_handlers
dybatpho::progress "Running ${kind} to install ${name}"

export GOBIN="$(dybatpho::path_join "$HOME" ".local" "bin")"
export CARGO_INSTALL_ROOT="$(dybatpho::path_join "$HOME" ".local")"
EOF
  printf '%s\n' "${content}" >> "${path}"
}

#######################################
# @description Iterate over tools defined in the YAML file and install them
# @arg $1 string Command to run when iterate over tools
# @env TOOL string Tool name to install, if set to "@empty", all tools for the specified method will be installed
# @env METHOD string Method to use for the tool installation: "shell", "os", "binary", "mise"
#######################################
# shellcheck disable=SC2153
function dytoy::iterate {
  local command
  dybatpho::expect_args command -- "$@"
  dybatpho::is function "$command" \
    || dybatpho::die "${command} function of ${METHOD} method is not defined"
  if [[ "$TOOL" == "@empty" ]]; then
    dybatpho::info "Install ${METHOD} tools"
    readarray -t tools < <(
      dybatpho::yaml_query "$(dytoy::yaml_file)" \
        "filter(.method == \"${METHOD}\" and .enabled != \"false\") | .[].name" \
        -r -o=j -I=0
    )
    for tool in "${tools[@]}"; do
      "$command" "$tool"
    done
    dybatpho::success "Installed all ${METHOD} tools"
  else
    dybatpho::info "Install ${METHOD} tool: ${TOOL}"
    "$command" "$TOOL"
  fi
}

#######################################
# @description Check if the tool is defined in the YAML file
# @arg $1 string Name of tool
# @arg $2 string Method to use for the tool
#######################################
function dytoy::is_defined {
  local name method
  dybatpho::expect_args name method -- "$@"
  local yaml
  yaml=$(dytoy::get_yaml "$name" "all" "$method")
  [[ "$yaml" == "[]" ]] || dybatpho::is empty "$yaml" \
    && dybatpho::die "Not found $name tool in $(dytoy::yaml_file)"
  local is_enabled
  is_enabled=$(dytoy::get_yaml "$name" "enabled")
  dybatpho::is false "$is_enabled" \
    && dybatpho::die "Tool $name is disabled"
}

#######################################
# @description Check if the tool is essential and dytoy scripts consider it invalid
# @arg $1 string Name of tool
# @env ONLY_ESSENTIAL boolean Flag to check if only essential tools should be considered
#######################################
function dytoy::is_invalid_essential {
  local name
  dybatpho::expect_args name -- "$@"
  local is_essential
  is_essential=$(dytoy::get_yaml "$name" "is_essential")
  dybatpho::is true "$ONLY_ESSENTIAL" && ! dybatpho::is true "$is_essential"
}

#######################################
# @description Check if command tool is not installed or installed but in force mode
# @arg $1 string Name of tool
# @arg $2 string Location of tool
# @env ONLY_NOT_INSTALLED boolean Flag to install only not installed tool
#######################################
function dytoy::is_installed_command {
  local name
  dybatpho::expect_args name -- "$@"
  local location="${2:-$(dybatpho::path_join "$HOME" ".local" "bin")}"
  if dybatpho::is true "$ONLY_NOT_INSTALLED"; then
    if dybatpho::is command "$name" || dybatpho::is file "$(dybatpho::path_join "$location" "$name")"; then
      dybatpho::debug "$name tool is already installed, skipping"
      return 0
    fi
    return 1
  fi
  return 1
}

#######################################
# @description Check if package tool is not installed or installed but in force mode
# @arg $1 string Package name
# @arg $2 string Tool to use for package management (e.g., "portage", "pacman", "apt", "apk", "brew", "mas", "dmg", "fdroidcl")
# @env ONLY_NOT_INSTALLED boolean Flag to install only not installed tool
#######################################
function dytoy::is_installed_package {
  local name pkg_tool
  dybatpho::expect_args name pkg_tool -- "$@"
  if dybatpho::is true "$ONLY_NOT_INSTALLED"; then
    if "pkg::check_installed_${pkg_tool}" "$name"; then
      dybatpho::debug "$name package is already installed, skipping."
      return 0
    else
      return 1
    fi
  fi
  return 1
}

#######################################
# @description Enable service with init system from the YAML file
# @arg $1 string YAML content
# @arg $2 string Init system of machine
#######################################
function dytoy::enable_service {
  local yaml init_system
  dybatpho::expect_args yaml init_system -- "$@"

  local service_name
  service_name=$(dytoy::get_field "$yaml" "service")
  if [[ "$service_name" == "null" ]]; then
    return 0
  fi
  local is_user_service
  is_user_service=$(dytoy::get_field "$yaml" "is_user_service")
  "init::enable_${init_system}_service" "$service_name" "$is_user_service"
}

#######################################
# @description Install a package when it isn't installed yet, then enable its service
# @arg $1 string Package name
# @arg $2 string Tool to use for checking installation (e.g., "portage", "apt")
# @arg $3 string Init system to enable the service of the package with, empty to skip
# @arg $4 string YAML content, used to look up the service
# @arg $@ string Command installing the package
#######################################
function dytoy::install_package {
  local name pkg_tool init_system yaml
  dybatpho::expect_args name pkg_tool init_system yaml -- "$@"
  shift 4
  if dytoy::is_installed_package "$name" "$pkg_tool"; then
    return 0
  fi
  "$@" || dybatpho::die "Can't install $name"
  dybatpho::debug "Installed $name"
  [[ -z "$init_system" ]] || dytoy::enable_service "$yaml" "$init_system"
}

#######################################
# @description Install Gentoo package from the YAML file
# @arg $1 string YAML content
# @arg $2 string Init system of machine
#######################################
function dytoy::install_gentoo_package {
  local yaml init_system
  dybatpho::expect_args yaml init_system -- "$@"
  local name repo url
  name=$(dytoy::get_field "$yaml" "name")
  repo=$(dytoy::get_field "$yaml" "repo")
  url=$(dytoy::get_field "$yaml" "url")
  [[ "$repo" == "null" ]] || pkg::add_overlay "$repo" "$url" > /dev/null

  dytoy::install_package "$name" "portage" "$init_system" "$yaml" \
    pkg::install_via_portage "$name"
}

#######################################
# @description Install Arch package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_arch_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  local name
  name=$(dytoy::get_field "$yaml" "name")
  dytoy::install_package "$name" "pacman" "systemd" "$yaml" \
    pkg::install_via_pacman "$name"
}

#######################################
# @description Add an APT repository from the YAML file
# @arg $1 string YAML content
# @arg $2 string OS type (e.g., "ubuntu", "debian", "termux")
#######################################
function dytoy::add_apt_repo {
  local yaml os
  dybatpho::expect_args yaml os -- "$@"
  local name repo
  name=$(dytoy::get_field "$yaml" "name")
  repo=$(dytoy::get_field "$yaml" "repo")
  [[ "$repo" == "null" ]] && return

  local repo_name components suite key
  repo_name=$(dytoy::get_field "$yaml" "repo_name")
  components=$(dytoy::get_field "$yaml" "components")
  suite=$(dytoy::get_field "$yaml" "suite")
  key=$(dytoy::get_field "$yaml" "key")

  [[ "$repo_name" == "null" ]] && repo_name=$name
  if [[ "$suite" == "null" ]]; then
    case "$os" in
      ubuntu)
        suite=$(grep -is UBUNTU_CODENAME /etc/os-release | cut -d= -f2)
        ;;
      debian)
        suite=$(grep -is VERSION_CODENAME /etc/os-release | cut -d= -f2)
        ;;
      termux)
        suite=""
        ;;
    esac
  fi
  local url="${repo//%v/${suite}}"
  pkg::add_apt_repo "$repo_name" "$url" "$suite" "$components" "$key"
  pkg::sync_apt_repo
}

#######################################
# @description Install Ubuntu package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_ubuntu_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  dytoy::add_apt_repo "$yaml" "ubuntu"

  local name
  name=$(dytoy::get_field "$yaml" "name")
  dytoy::install_package "$name" "apt" "systemd" "$yaml" \
    pkg::install_via_apt "$name"
}

#######################################
# @description Install Alpine package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_alpine_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  local name
  name=$(dytoy::get_field "$yaml" "name")
  dytoy::install_package "$name" "apk" "openrc" "$yaml" \
    pkg::install_via_apk "$name"
}

#######################################
# @description Install Termux package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_termux_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  local name
  name=$(dytoy::get_field "$yaml" "name")
  dytoy::install_package "$name" "apt" "termux" "$yaml" \
    pkg::install_via_termux "$name"
}

#######################################
# @description Install F-Droid app from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_fdroid_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  local name repo url
  name=$(dytoy::get_field "$yaml" "name")
  repo=$(dytoy::get_field "$yaml" "repo")
  url=$(dytoy::get_field "$yaml" "url")
  [[ "$repo" == "null" ]] || pkg::add_fdroid_repo "$repo" "$url" > /dev/null

  dytoy::install_package "$name" "fdroidcl" "" "$yaml" \
    pkg::install_via_fdroidcl "$name"
}

#######################################
# @description Install Flatpak package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_flatpak_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  local name repo url
  name=$(dytoy::get_field "$yaml" "name")
  repo=$(dytoy::get_field "$yaml" "repo")
  url=$(dytoy::get_field "$yaml" "url")
  [[ "$repo" == "null" ]] || pkg::add_flatpak_repo "$repo" "$url" > /dev/null

  dytoy::install_package "$name" "flatpak" "" "$yaml" \
    pkg::install_via_flatpak "$name" "$repo"
}

#######################################
# @description Install MacOS package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_macos_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  local name type
  name=$(dytoy::get_field "$yaml" "name")
  type=$(dytoy::get_field "$yaml" "type")
  case "$type" in
    store)
      dytoy::install_package "$name" "mas" "" "$yaml" \
        pkg::install_via_mas "$name"
      ;;
    download)
      local url
      url=$(dytoy::get_field "$yaml" "url")
      dytoy::install_package "$name" "dmg" "" "$yaml" \
        pkg::install_via_dmg "$name" "$url"
      ;;
    *)
      local unstable
      local -a brew_params=()
      unstable=$(dytoy::get_field "$yaml" "unstable")
      if [[ "$type" == "cask" ]]; then
        brew_params=("--cask")
      else
        brew_params=("--formula")
      fi
      if [[ "$unstable" == "true" ]]; then
        brew_params+=("--HEAD")
      fi
      local repo
      repo=$(dytoy::get_field "$yaml" "repo")
      [[ "$repo" == "null" ]] || pkg::add_brew_tap "$repo" > /dev/null
      dytoy::install_package "$name" "brew" "launchd" "$yaml" \
        pkg::install_via_brew "$name" "${brew_params[@]}"
      ;;
  esac
}

#######################################
# @description Install Rosetta on MacOS
# @noargs
#######################################
function dytoy::install_macos_rosetta {
  ! dybatpho::is file /usr/libexec/rosetta/runtime \
    && softwareupdate --install-rosetta --agree-to-license
}
