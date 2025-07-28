#!/usr/bin/env bash
# shellcheck disable=2154,2155

#######################################
# @description Get YAML content for a specific tool
# @arg $1 string Name of tool
# @arg $2 string Field to extract from the YAML file, `all` to get all fields
# @arg $3 string Method to filter by, only used when field is `all`
#######################################
function dytoy::get_yaml {
  local name field
  dybatpho::expect_args name field -- "$@"
  case $field in
    all)
      local method="${3:-}"
      yq e -o=j -I=0 \
        "filter(.name == \"${name}\" and .method == \"${method}\") | .[]" \
        ~/.config/dytoy/tools.yaml
      ;;
    dependencies | archive | *.packages | *.services)
      yq e -o=j -I=0 \
        "filter(.name == \"${name}\") | .[].${field}.[]" \
        ~/.config/dytoy/tools.yaml
      ;;
    *)
      yq e -o=j -I=0 -r \
        "filter(.name == \"${name}\") | .[].${field}" \
        ~/.config/dytoy/tools.yaml
      ;;
  esac
}

#######################################
# @description Install dependencies from the YAML file
# @arg $1 string Name of tool
#######################################
function dytoy::install_dependencies {
  local name
  dybatpho::expect_args name -- "$@"
  readarray dependencies < <(dytoy::get_yaml "$name" "dependencies")
  for dependency in "${dependencies[@]}"; do
    dybatpho::debug "Need dependency: $dependency"
    dependency=${dependency%$'\n'}
    local method=$(dytoy::get_yaml "$dependency" "method")
    dybatpho::dry_run "$HOME/.local/bin/dytoy_${method}" -i -t "$dependency"
  done
}

#######################################
# @description Run a script
# @arg $1 string Script file path
# @env DRY_RUN boolean If true, show the script file instead of running it
#######################################
function dytoy::run_script {
  local script_file
  dybatpho::expect_args script_file -- "$@"
  if dybatpho::is true "$DRY_RUN"; then
    echo "DRY_RUN: $script_file"
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

  if [ "$content" != "null" ]; then
    local lib_dir
    lib_dir=$(dirname "${BASH_SOURCE[0]}")
    cat << EOF > "${path}"
. ${lib_dir}/dybatpho/init.sh
dybatpho::register_err_handler
dybatpho::progress "Running ${kind} to install ${name}"
EOF
    echo -e "${content}" >> "${path}"
  fi
}

#######################################
# @description Iterate over tools defined in the YAML file and install them
# @env TOOL string Tool name to install, if set to "@empty", all tools for the specified method will be installed
# @env METHOD string Method to use for the tool installation: "shell", "os", "binary", "mise"
#######################################
function dytoy::iterate {
  if [ "$TOOL" = "@empty" ]; then
    dybatpho::info "Install ${METHOD} tools"
    readarray tools < <(
      yq e -r -o=j -I=0 "filter(.method == \"${METHOD}\") | .[].name" \
        ~/.config/dytoy/tools.yaml
    )
    for tool in "${tools[@]}"; do
      tool=${tool%$'\n'}
      _install_tool "$tool"
    done
    dybatpho::success "Installed all ${METHOD} tools"
  else
    dybatpho::info "Install ${METHOD} tool: ${TOOL}"
    # HACK: Need to define _install_tool function before calling it
    dybatpho::is function "_install_tool" && _install_tool "$TOOL" \
      || dybatpho::die "Function _install_tool of method ${METHOD} is not defined"
  fi
}

#######################################
# @description Check if the tool is defined in the YAML file
# @arg $1 string Name of tool
# @arg $1 string Method to use for the tool
#######################################
function dytoy::is_defined {
  local name method
  dybatpho::expect_args name method -- "$@"
  local yaml=$(dytoy::get_yaml "$name" "all" "$method")
  dybatpho::is empty "$yaml" \
    && dybatpho::die "Tool $name not found in ~/.config/dytoy/tools.yaml"
}

#######################################
# @description Check if the tool is essential and dytoy scripts consider it invalid
# @arg $1 string Name of tool
# @env ONLY_ESSENTIAL boolean Flag to check if only essential tools should be considered
#######################################
function dytoy::is_invalid_essential {
  local name
  dybatpho::expect_args name -- "$@"
  local is_essential=$(dytoy::get_yaml "$name" "is_essential")
  dybatpho::is true "$ONLY_ESSENTIAL" && ! dybatpho::is true "$is_essential"
}

#######################################
# @description Check if command tool is not installed or installed but in force mode
# @arg $1 string Name of tool
# @arg $2 string Command to execute when tool is installed, default is the name of the tool
# @env ONLY_NOT_INSTALLED boolean Flag to install only not installed tool
#######################################
function dytoy::is_installed_command {
  local name
  dybatpho::expect_args name -- "$@"
  local command="${2:-$name}"
  if dybatpho::is true "$ONLY_NOT_INSTALLED" \
    && dybatpho::is command "$command"; then
    dybatpho::debug "Tool $name is already installed, skipping"
    return 0
  fi
  return 1
}

#######################################
# @description Check if package tool is not installed or installed but in force mode
# @arg $1 string Package name
# @arg $2 string Tool to use for package management (e.g., "portage", "pacman", "apt", "apk", "brew", "mas", "dmg")
# @env ONLY_NOT_INSTALLED boolean Flag to install only not installed tool
#######################################
function dytoy::is_installed_package {
  local name pkg_tool
  dybatpho::expect_args name pkg_tool -- "$@"
  if dybatpho::is true "$ONLY_NOT_INSTALLED"; then
    local method
    if eval "pkg::check_installed_${pkg_tool} \"${name}\""; then
      dybatpho::debug "Package $name is already installed, skipping."
      return 0
    else
      return 1
    fi
  fi
  return 1
}

#######################################
# @description Install Gentoo package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_gentoo_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  local name=$(echo "$yaml" | yq e '.name')
  local repo=$(echo "$yaml" | yq e '.repo')
  local url=$(echo "$yaml" | yq e '.url')
  [[ "$repo" != "null" ]] && pkg::add_overlay "$repo" "$url" > /dev/null

  ! dytoy::is_installed_package "$name" "portage" \
    && pkg::install_via_portage "$name" \
    && dybatpho::debug "Installed package: $name" \
    || :
}

#######################################
# @description Install Arch package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_arch_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  local name=$(echo "$yaml" | yq e '.name')
  ! dytoy::is_installed_package "$name" "pacman" \
    && pkg::install_via_pacman "$name" \
    && dybatpho::debug "Installed package: $name" \
    || :
}

#######################################
# @description Add an APT repository from the YAML file
# @arg $1 string YAML content
# @arg $2 string OS type (e.g., "ubuntu", "debian", "termux")
#######################################
function dytoy::add_apt_repo {
  local yaml os
  dybatpho::expect_args yaml os -- "$@"
  local name=$(echo "$yaml" | yq e '.name')
  local repo=$(echo "$yaml" | yq e '.repo')
  [[ "$repo" == "null" ]] && return

  repo_name=$(echo "$yaml" | yq e '.repo_name')
  repo_version=$(echo "$yaml" | yq e '.repo_version')
  distro_version=$(echo "$yaml" | yq e '.distro_version')
  key=$(echo "$yaml" | yq e '.key')

  [[ "$repo_name" == "null" ]] && repo_name=$name
  if [[ "$distro_version" == "null" ]]; then
    case "$os" in
      ubuntu)
        distro_version=$(grep -is UBUNTU_CODENAME /etc/os-release | cut -d= -f2)
        ;;
      debian)
        distro_version=$(grep -is VERSION_CODENAME /etc/os-release | cut -d= -f2)
        ;;
      termux)
        distro_version=""
        ;;
    esac
  fi
  repo_code="${repo//%v/${distro_version}}"
  pkg::add_apt_repo "$repo_name" "$repo_code" "$distro_version" "$repo_version" "$key"
  pkg::sync_ubuntu_repo
}

#######################################
# @description Install Ubuntu package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_ubuntu_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  dytoy::add_apt_repo "$yaml" "ubuntu"

  local name=$(echo "$yaml" | yq e '.name')
  ! dytoy::is_installed_package "$name" "apt" \
    && pkg::install_via_apt "$name" \
    && dybatpho::debug "Installed package: $name" \
    || :
}

#######################################
# @description Install Alpine package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_alpine_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  local name=$(echo "$yaml" | yq e '.name')
  ! dytoy::is_installed_package "$name" "apk" \
    && pkg::install_via_apk "$name" \
    && dybatpho::debug "Installed package: $name" \
    || :
}

#######################################
# @description Install Termux package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_termux_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  local name=$(echo "$yaml" | yq e '.name')
  dytoy::add_apt_repo "$name" "$yaml" "termux"
  ! dytoy::is_installed_package "$name" "apt" \
    && pkg::install_via_termux "$name" \
    && dybatpho::debug "Installed package: $name" \
    || :
}

#######################################
# @description Install Flatpak package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_flatpak_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  local name=$(echo "$yaml" | yq e '.name')
  local repo=$(echo "$yaml" | yq e '.repo')
  local url=$(echo "$yaml" | yq e '.url')
  [[ "$repo" != "null" ]] && pkg::add_flatpak_repo "$repo" "$url" > /dev/null

  ! dytoy::is_installed_package "$name" "flatpak" \
    && pkg::install_via_flatpak "$name" "$repo" \
    && dybatpho::debug "Installed flatpak application: $name" \
    || :
}

#######################################
# @description Install MacOS package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_macos_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  local name=$(echo "$yaml" | yq e '.name')
  local type=$(echo "$yaml" | yq e '.type')
  case "$type" in
    store)
      ! dytoy::is_installed_package "$name" "mas" \
        && pkg::install_via_mas "$name" \
        && dybatpho::debug "Installed package: $name" \
        || :
      ;;
    download)
      url=$(echo "$yaml" | yq e '.url')
      ! dytoy::is_installed_package "$name" "dmg" \
        && pkg::install_via_dmg "$name" "$url" \
        && dybatpho::debug "Installed package: $name" \
        || :
      ;;
    *)
      unstable=$(echo "$yaml" | yq e '.unstable')
      if [[ "$type" == "cask" ]]; then
        brew_param="--cask"
      else
        brew_param="--formula"
      fi
      if [[ "$unstable" == "true" ]]; then
        brew_param="$brew_param --HEAD"
      fi
      ! dytoy::is_installed_package "$name" "brew" \
        && pkg::install_via_brew "$name" "$brew_param" \
        && dybatpho::debug "Installed package: $name" \
        || :
      ;;
  esac
}

#######################################
# @description Install Rosetta on MacOS
#######################################
function dytoy::install_macos_rosetta {
  ! dybatpho::is file /usr/libexec/rosetta/runtime \
    && softwareupdate --install-rosetta --agree-to-license \
    || :
}
