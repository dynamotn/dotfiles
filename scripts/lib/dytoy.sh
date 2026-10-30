#!/usr/bin/env bash
# shellcheck disable=SC2154 # DRY_RUN, TOOL, METHOD and ONLY_* are set by the dytoy CLI
# @file dytoy.sh
# @brief Library `dytoy` to read the tools YAML file and install what it describes
# @description Library `dytoy` to read the tools YAML file and install what it
# describes. Queries go through the `json` module of dybatpho instead of calling
# `yq` by hand, and every distro installer shares `dytoy::install_package`.
dybatpho::load json os semver cache

# Seconds the state of a tool installed by a whole-method run stays valid, so
# a run that failed half way resumes after the last tool that succeeded.
DYTOY_STATE_TTL="${DYTOY_STATE_TTL:-604800}"
# The key of this OS in a tool's YAML, such as `gentoo` or `macos`, empty when
# no package manager is known for it; the installed `dytoy` sets it.
DYTOY_OS="${DYTOY_OS:-}"

#######################################
# @description Print the path of the tools YAML file
# @noargs
#######################################
function dytoy::yaml_file {
  local config_dir
  config_dir="$(dybatpho::xdg_config_dir dytoy)"
  dybatpho::path_join "${config_dir}" "tools.yaml"
}

#######################################
# @description Run a command and split what it prints into an array, one line
# per element
# @arg $1 string Name of the array variable to fill
# @arg $@ string Command and its arguments
# @set The named array: one line per element, empty when nothing is printed.
# It holds what the command printed even when the command fails.
# @exitcode The exit code of the command
# @internal
#######################################
function __dytoy_lines_into {
  local __dytoy_lines_var
  dybatpho::expect_args __dytoy_lines_var -- "$@"
  shift
  local -n __dytoy_lines_ref="${__dytoy_lines_var}"
  __dytoy_lines_ref=()
  local __dytoy_lines_output __dytoy_lines_status=0
  __dytoy_lines_output="$("$@")" || __dytoy_lines_status=$?
  [[ -z "${__dytoy_lines_output}" ]] \
    || readarray -t __dytoy_lines_ref <<< "${__dytoy_lines_output}"
  return "${__dytoy_lines_status}"
}

#######################################
# @description Get a field of a YAML content of a tool
# @arg $1 string YAML content
# @arg $2 string Field to extract, as a `jq` expression without the leading dot
#######################################
function dytoy::get_field {
  local yaml field
  dybatpho::expect_args yaml field -- "$@"
  dybatpho::json_get "${yaml}" ".${field}"
}

#######################################
# @description Read the `params` of a package, the extra flags handed to its
# package manager
# @arg $1 string Name of the array variable to fill
# @arg $2 string YAML content of the package
# @set The named array: one flag per element, empty when unset
#######################################
function dytoy::get_params_into {
  local __dytoy_params_var __dytoy_params_yaml
  dybatpho::expect_args __dytoy_params_var __dytoy_params_yaml -- "$@"
  local -n __dytoy_params_ref="${__dytoy_params_var}"
  # A package whose params can't be read is installed without them.
  __dytoy_lines_into "${__dytoy_params_var}" \
    dytoy::get_field "${__dytoy_params_yaml}" "params // [] | .[]" \
    || dybatpho::debug "Can't read params, installing without them"
}

#######################################
# @description Print the release of the OS this machine runs, the version that
# the `releases` of a package are matched against
# @noargs
# @stdout The release, such as `24.04` on Ubuntu or `15.1` on macOS
# @env DYTOY_RELEASE string Release to use instead of the detected one
# @exitcode 1 The OS publishes no release, as on Arch
#######################################
function dytoy::get_release {
  if [[ -n "${DYTOY_RELEASE:-}" ]]; then
    printf '%s\n' "${DYTOY_RELEASE}"
    return 0
  fi
  dybatpho::distro_version
}

#######################################
# @description Check if a package is meant for the release of this OS: it has
# no `releases`, or the release satisfies one of them
# @arg $1 string YAML content of the package
# @exitcode 0 The package should be installed here
# @exitcode 1 It is meant for other releases
#######################################
function dytoy::is_package_for_release {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  local -a releases
  # Releases that can't be read restrict nothing.
  __dytoy_lines_into releases dytoy::get_field "${yaml}" "releases // [] | .[]" \
    || dybatpho::debug "Can't read releases, matching every release"
  ((${#releases[@]})) || return 0
  local name release range
  name=$(dytoy::get_field "${yaml}" "name")
  # A release such as Arch's `rolling` is no version, so no range can hold it.
  if ! release=$(dytoy::get_release) \
    || ! release=$(dybatpho::semver_coerce "${release}" 2> /dev/null); then
    dybatpho::debug "Skip ${name}: this OS publishes no release to match ${releases[*]}"
    return 1
  fi
  for range in "${releases[@]}"; do
    dybatpho::semver_satisfies "${release}" "${range}" && return 0
  done
  dybatpho::debug "Skip ${name}: release ${release} satisfies none of ${releases[*]}"
  return 1
}

#######################################
# @description Print the package an OS package manager should install for the
# version a package entry asks for
# @arg $1 string Package manager, one of "portage", "pacman", "apt", "termux" or "apk"
# @arg $2 string Package name
# @arg $3 string Version: `latest` or `null` for the default one, `HEAD` for
#   the development branch, anything else for that exact version
# @stdout The package to install, such as `=app-editors/neovim-9999`,
#   `neovim-git` or `ripgrep=14.1.0-1`
#######################################
function dytoy::get_package_spec {
  local manager name version
  dybatpho::expect_args manager name version -- "$@"
  case "${version}" in
    null | latest)
      printf '%s\n' "${name}"
      return 0
      ;;
    *) ;;
  esac
  case "${manager}" in
    # The live ebuild of a Gentoo package builds its development branch.
    portage)
      [[ "${version}" != "HEAD" ]] || version="9999"
      printf '=%s-%s\n' "${name}" "${version}"
      ;;
    # The AUR carries the development branch as `<name>-git`, and paru can't
    # pick an older version.
    pacman)
      [[ "${version}" == "HEAD" ]] \
        || dybatpho::die "pacman can't install version ${version} of ${name}, only HEAD"
      printf '%s-git\n' "${name}"
      ;;
    apt | termux | apk)
      [[ "${version}" != "HEAD" ]] \
        || dybatpho::die "${manager} can't install the HEAD of ${name}"
      printf '%s=%s\n' "${name}" "${version}"
      ;;
    *) dybatpho::die "Version of ${name} isn't supported with ${manager}" ;;
  esac
}

#######################################
# @description Run a `jq` filter over the tools of the YAML file, read as JSON
#   with its anchors already resolved. Each result is printed on its own line:
#   a string raw, anything else as compact JSON, so a caller can query an
#   object again with `dybatpho::json_get`.
# @arg $1 string `jq` filter
# @arg $@ string Further `jq` options, such as `--arg name value`
# @stdout One result per line
# @internal
#######################################
function __dytoy_query_tools {
  local filter
  dybatpho::expect_args filter -- "$@"
  shift
  local yaml_file document
  yaml_file="$(dytoy::yaml_file)"
  document="$(dybatpho::yaml_to_json "${yaml_file}")" || return
  dybatpho::json_query - "${filter}" -c -r "$@" <<< "${document}"
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
  case ${field} in
    all)
      # Every definition of the tool for that method, as one JSON array
      # dyshellint disable=SC2016 $name and $method are jq variables, set by --arg
      filter='[.[] | select(.name == $name and .method == $method)]'
      ;;
    archive | *.packages | *.services | dependencies | params)
      # One line per entry; a tool without the list has none
      filter=".[] | select(.name == \$name) | (.${field} // []) | .[]"
      ;;
    *)
      # `null` for a field the tool does not set
      filter=".[] | select(.name == \$name) | .${field}"
      ;;
  esac
  __dytoy_query_tools "${filter}" --arg name "${name}" --arg method "${3:-}"
}

#######################################
# @description Print a field of a tool, or a default when the tool leaves it
# unset or empty
# @arg $1 string Name of tool
# @arg $2 string Field to extract
# @arg $3 string Default value, which may be empty
# @stdout The field or the default
#######################################
function dytoy::get_yaml_or {
  local name field
  dybatpho::expect_args name field -- "$@"
  local value
  value=$(dytoy::get_yaml "${name}" "${field}")
  [[ -n "${value}" && "${value}" != "null" ]] || value="${3:-}"
  printf '%s\n' "${value}"
}

#######################################
# @description Print the version a tool asks for, `latest` when it names none
# @arg $1 string Name of tool
# @arg $2 string Field holding the version, `version` by default
# @stdout The version
#######################################
function dytoy::get_version {
  local name
  dybatpho::expect_args name -- "$@"
  dytoy::get_yaml_or "${name}" "${2:-version}" "latest"
}

#######################################
# @description Install dependencies from the YAML file
# @arg $1 string Name of tool
#######################################
function dytoy::install_dependencies {
  local name
  dybatpho::expect_args name -- "$@"
  local -a dependencies
  __dytoy_lines_into dependencies dytoy::get_yaml "${name}" "dependencies" \
    || dybatpho::debug "Can't read dependencies of ${name}"
  local dytoy_bin dependency method
  dytoy_bin="$(dybatpho::path_join "${HOME}" ".local" "bin" "dytoy")"
  for dependency in "${dependencies[@]}"; do
    dybatpho::debug "Need dependency: ${dependency}"
    method=$(dytoy::get_yaml "${dependency}" "method")
    dybatpho::dry_run "${dytoy_bin}" "${method}" -i -t "${dependency}"
  done
}

#######################################
# @description Run a script, or show what it contains in dry run mode
# @arg $1 string Script file path
# @env DRY_RUN boolean If true, show the script file instead of running it
#######################################
function dytoy::run_script {
  # Prefixed, as the script sourced here would otherwise see these locals.
  local __dytoy_run_script_file
  dybatpho::expect_args __dytoy_run_script_file -- "$@"
  # A tool without a hook still gets a temp file, and reporting an empty script
  # as something about to run says nothing.
  if ! dybatpho::is file "${__dytoy_run_script_file}"; then
    dybatpho::debug "No script at ${__dytoy_run_script_file}, skipping"
    return 0
  fi
  local __dytoy_run_script_content
  __dytoy_run_script_content="$(< "${__dytoy_run_script_file}")"
  if dybatpho::string_is_blank "${__dytoy_run_script_content}"; then
    dybatpho::debug "Nothing to run in ${__dytoy_run_script_file}, skipping"
    return 0
  fi
  if dybatpho::is true "${DRY_RUN}"; then
    # The contents go to stderr, so the header goes with them rather than to
    # stdout where the two would be separated.
    dybatpho::info "RUN: ${__dytoy_run_script_file}"
    dybatpho::show_file "${__dytoy_run_script_file}"
  else
    # shellcheck disable=1090
    . "${__dytoy_run_script_file}"
  fi
  # Clear the script file after running
  printf '\n' > "${__dytoy_run_script_file}"
}

#######################################
# @description Create a script file with the given content to install a tool
# @arg $1 string Name of the tool
# @arg $2 string Path of the script file to create
# @arg $3 string Content of the script
# @arg $4 string Kind of script (e.g., shell, before-install hook, after-install hook)
# @arg $5 string Version of the tool, exported to the script as `DYTOY_VERSION` (optional)
#######################################
function dytoy::create_script {
  local name path content kind
  dybatpho::expect_args name path content kind -- "$@"
  local version="${5:-}"
  if [[ "${content}" == "null" ]] || dybatpho::string_is_blank "${content}"; then
    return 0
  fi

  local lib_dir init_file bin_dir local_dir
  lib_dir="$(dybatpho::path_dirname "${BASH_SOURCE[0]}")"
  init_file="$(dybatpho::path_join "${lib_dir}" "dybatpho" "init.sh")"
  local_dir="$(dybatpho::path_join "${HOME}" ".local")"
  bin_dir="$(dybatpho::path_join "${local_dir}" "bin")"
  # `dytoy::run_script` sources this into a shell that already has dybatpho.
  # Sourcing `init.sh` again there would reset its cleanup registry, so every
  # temp file registered before the hook would be left behind.
  {
    printf 'if declare -F dybatpho::load > /dev/null; then\n'
    printf '  dybatpho::load network\n'
    printf 'else\n'
    printf '  . %q --modules network\n' "${init_file}"
    printf '  dybatpho::register_common_handlers\n'
    printf 'fi\n'
  } > "${path}"
  cat << EOF >> "${path}"
dybatpho::progress "Running ${kind} to install ${name}"

export GOBIN="${bin_dir}"
export CARGO_INSTALL_ROOT="${local_dir}"
EOF
  if ! dybatpho::string_is_blank "${version}"; then
    printf 'export DYTOY_VERSION=%q\n' "${version}" >> "${path}"
  fi
  printf '%s\n' "${content}" >> "${path}"
}

#######################################
# @description Run the hooks of a tool for one stage of its installation.
#   The top-level `hook` runs for every method and every OS. An OS section
#   may carry a `hook` of its own, for what only that distro needs, and it
#   runs inside the top-level one: after it before the install, ahead of it
#   after the install.
# @arg $1 string Name of tool
# @arg $2 string Stage, `before` or `after`
# @arg $3 string OS section whose own hook runs too (e.g., "arch"), empty for none
# @arg $4 string Version of the tool, exported to the hooks as `DYTOY_VERSION` (optional)
#######################################
function dytoy::run_hook {
  local name stage
  dybatpho::expect_args name stage -- "$@"
  local section="${3:-}" version="${4:-}"
  case "${stage}" in
    before)
      dytoy::run_section_hook "${name}" before "" "${version}"
      [[ -z "${section}" ]] || dytoy::run_section_hook "${name}" before "${section}" "${version}"
      ;;
    after)
      [[ -z "${section}" ]] || dytoy::run_section_hook "${name}" after "${section}" "${version}"
      dytoy::run_section_hook "${name}" after "" "${version}"
      ;;
    *) dybatpho::die "Unknown hook stage: ${stage}" ;;
  esac
}

#######################################
# @description Run the hook of one section of a tool for one stage, and no
#   other: the top-level `hook` when no section is named, otherwise the one of
#   that section, such as `flatpak` around the Flatpak packages it installs.
# @arg $1 string Name of tool
# @arg $2 string Stage, `before` or `after`
# @arg $3 string Section whose hook runs (e.g., "arch", "flatpak"), empty for the top-level one
# @arg $4 string Version of the tool, exported to the hook as `DYTOY_VERSION` (optional)
#######################################
function dytoy::run_section_hook {
  local name stage
  dybatpho::expect_args name stage -- "$@"
  local section="${3:-}" version="${4:-}"
  case "${stage}" in
    before | after) ;;
    *) dybatpho::die "Unknown hook stage: ${stage}" ;;
  esac
  local field="hook.${stage}" kind="${stage}-hook"
  if [[ -n "${section}" ]]; then
    field="${section}.${field}"
    kind="${section} ${kind}"
  fi

  local content path
  # A hook that cannot be read renders as an empty script, as it always has.
  content="$(dytoy::get_yaml "${name}" "${field}")" || true
  dybatpho::create_temp path ".sh"
  dytoy::create_script "${name}" "${path}" "${content}" "${kind}" "${version}"
  dytoy::run_script "${path}"
}

#######################################
# @description Iterate over tools defined in the YAML file and install them
# @arg $1 string Command to run when iterate over tools
# @env TOOL string Tool name to install, if set to "@empty", all tools for the specified method will be installed
# @env METHOD string Method to use for the tool installation: "shell", "os", "binary", "mise"
# @env ONLY_NOT_INSTALLED boolean Skip the tools an earlier run of every tool
# installed, until their definition changes or `DYTOY_STATE_TTL` seconds pass
#######################################
# shellcheck disable=SC2153
function dytoy::iterate {
  # Prefixed, as the command run for each tool would otherwise see these locals.
  local __dytoy_iterate_command
  dybatpho::expect_args __dytoy_iterate_command -- "$@"
  dybatpho::is function "${__dytoy_iterate_command}" \
    || dybatpho::die "${__dytoy_iterate_command} function of ${METHOD} method is not defined"
  if [[ "${TOOL}" == "@empty" ]]; then
    dybatpho::info "Install ${METHOD} tools"
    local __dytoy_iterate_yaml_file __dytoy_iterate_tool
    local -a __dytoy_iterate_tools
    __dytoy_iterate_yaml_file="$(dytoy::yaml_file)"
    # dyshellint disable=SC2016 $method is a jq variable, set by --arg
    __dytoy_lines_into __dytoy_iterate_tools __dytoy_query_tools \
      '.[] | select(.method == $method and .enabled != false and .enabled != "false") | .name' \
      --arg method "${METHOD}" \
      || dybatpho::debug "Can't read tools from ${__dytoy_iterate_yaml_file}"
    local __dytoy_iterate_state
    for __dytoy_iterate_tool in "${__dytoy_iterate_tools[@]}"; do
      __dytoy_iterate_state="$(__dytoy_state_key "${__dytoy_iterate_tool}")"
      # `--no-check-installed` asks to install everything again.
      if dybatpho::is true "${ONLY_NOT_INSTALLED}" \
        && DYBATPHO_CACHE_NAMESPACE=dytoy dybatpho::cache_has "${__dytoy_iterate_state}" "${DYTOY_STATE_TTL}"; then
        dybatpho::debug "Skip ${__dytoy_iterate_tool}, installed by an earlier run"
        continue
      fi
      __dytoy_install_one "${__dytoy_iterate_command}" "${__dytoy_iterate_tool}"
      printf 'done\n' | DYBATPHO_CACHE_NAMESPACE=dytoy dybatpho::cache_set "${__dytoy_iterate_state}"
    done
    dybatpho::success "Installed all ${METHOD} tools"
  else
    dybatpho::info "Install ${METHOD} tool: ${TOOL}"
    __dytoy_install_one "${__dytoy_iterate_command}" "${TOOL}"
  fi
}

#######################################
# @description Install one tool with the installer of its method, once it is
# known to be defined and wanted by this run
# @arg $1 string Installer to run
# @arg $2 string Name of tool
# @env METHOD string Method being run
# @internal
#######################################
# dyshellint disable=SC2310 the dytoy predicates are meant to be tested here
function __dytoy_install_one {
  # Prefixed, as the installer run here would otherwise see these locals.
  local __dytoy_one_command __dytoy_one_tool
  dybatpho::expect_args __dytoy_one_command __dytoy_one_tool -- "$@"
  dytoy::is_defined "${__dytoy_one_tool}" "${METHOD}"
  dytoy::is_invalid_essential "${__dytoy_one_tool}" && return 0
  "${__dytoy_one_command}" "${__dytoy_one_tool}"
}

#######################################
# @description Print the key the state of a tool is remembered under. It hashes
# the definition of the tool, so editing the tool installs it again.
# @arg $1 string Name of tool
# @env METHOD string Method being run
# @env ONLY_ESSENTIAL boolean An essential-only run skips the other tools
# @stdout The key
# @internal
#######################################
function __dytoy_state_key {
  local name definition
  dybatpho::expect_args name -- "$@"
  definition="$(dytoy::get_yaml "${name}" "all" "${METHOD}")"
  dybatpho::cache_key "${METHOD}" "${name}" "${ONLY_ESSENTIAL}" "${definition}"
}

#######################################
# @description Check that the tool is defined in the YAML file and enabled
# @arg $1 string Name of tool
# @arg $2 string Method to use for the tool
# @exitcode 0 The tool is defined and enabled
# @stderr The reason, before stopping the script when it is missing or disabled
#######################################
function dytoy::is_defined {
  local name method
  dybatpho::expect_args name method -- "$@"
  local yaml
  yaml=$(dytoy::get_yaml "${name}" "all" "${method}")
  if [[ "${yaml}" == "[]" ]] || dybatpho::is empty "${yaml}"; then
    local yaml_file
    yaml_file="$(dytoy::yaml_file)"
    dybatpho::die "Not found ${name} tool in ${yaml_file}"
  fi
  local is_enabled
  is_enabled=$(dytoy::get_yaml "${name}" "enabled")
  if dybatpho::is false "${is_enabled}"; then
    dybatpho::die "Tool ${name} is disabled"
  fi
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
  is_essential=$(dytoy::get_yaml "${name}" "is_essential")
  dybatpho::is true "${ONLY_ESSENTIAL}" && ! dybatpho::is true "${is_essential}"
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
  dybatpho::is true "${ONLY_NOT_INSTALLED}" || return 1
  dytoy::has_command "${name}" "${2:-}" || return 1
  dybatpho::debug "${name} tool is already installed, skipping"
}

#######################################
# @description Check whether a tool is installed: its command is on `PATH` or
# its file is in the directory it installs to
# @arg $1 string Name of tool
# @arg $2 string Directory the tool installs to, `~/.local/bin` when empty
#######################################
function dytoy::has_command {
  local name
  dybatpho::expect_args name -- "$@"
  local location="${2:-}"
  [[ -n "${location}" ]] || location="$(dybatpho::path_join "${HOME}" ".local" "bin")"
  local tool_path
  tool_path="$(dybatpho::path_join "${location}" "${name}")"
  dybatpho::is command "${name}" || dybatpho::is file "${tool_path}"
}

#######################################
# @description Check if package tool is not installed or installed but in force mode
# @arg $1 string Package name
# @arg $2 string Tool to use for package management, one of "portage",
#   "pacman", "apt", "apk", "brew", "mas", "dmg" or "fdroidcl"
# @env ONLY_NOT_INSTALLED boolean Flag to install only not installed tool
#######################################
function dytoy::is_installed_package {
  local name pkg_tool
  dybatpho::expect_args name pkg_tool -- "$@"
  if dybatpho::is true "${ONLY_NOT_INSTALLED}"; then
    if "package_manager::check_installed_${pkg_tool}" "${name}"; then
      dybatpho::debug "${name} package is already installed, skipping."
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
  service_name=$(dytoy::get_field "${yaml}" "service")
  if [[ "${service_name}" == "null" ]]; then
    return 0
  fi
  # A container has no init system running, so nothing could start it.
  if [[ "${init_system}" == "none" || "${DYTOY_INIT_SYSTEM:-}" == "none" ]]; then
    dybatpho::debug "No init system: not enabling ${service_name}"
    return 0
  fi
  local is_user_service
  is_user_service=$(dytoy::get_field "${yaml}" "is_user_service")
  "init_system::enable_${init_system}_service" "${service_name}" "${is_user_service}"
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
  # Prefixed, as the install command would otherwise see these locals.
  local __dytoy_install_name __dytoy_install_tool __dytoy_install_init __dytoy_install_yaml
  dybatpho::expect_args __dytoy_install_name __dytoy_install_tool \
    __dytoy_install_init __dytoy_install_yaml -- "$@"
  shift 4
  if dytoy::is_installed_package "${__dytoy_install_name}" "${__dytoy_install_tool}"; then
    return 0
  fi
  "$@" || dybatpho::die "Can't install ${__dytoy_install_name}"
  dybatpho::debug "Installed ${__dytoy_install_name}"
  [[ -z "${__dytoy_install_init}" ]] \
    || dytoy::enable_service "${__dytoy_install_yaml}" "${__dytoy_install_init}"
}

#######################################
# @description Print the package manager asked whether a package of an OS is
# installed
# @arg $1 string Key of the OS in a tool's YAML, such as `gentoo`
# @stdout The manager, one `package_manager::check_installed_<manager>` takes
# @exitcode 1 No installer of this OS checks its packages
#######################################
function dytoy::package_checker {
  local os
  dybatpho::expect_args os -- "$@"
  case "${os}" in
    gentoo) printf 'portage\n' ;;
    arch) printf 'pacman\n' ;;
    ubuntu | termux) printf 'apt\n' ;;
    alpine) printf 'apk\n' ;;
    macos) printf 'brew\n' ;;
    *) return 1 ;;
  esac
}

#######################################
# @description Print the name a package is checked by, which differs from its
# own name for the version it asks for on some package managers
# @arg $1 string Key of the OS in a tool's YAML, such as `arch`
# @arg $2 string Package name
# @arg $3 string Version asked for, `null` or empty for the default one
# @stdout The name to check
#######################################
function dytoy::checked_package_name {
  local os name
  dybatpho::expect_args os name -- "$@"
  local version="${3:-}"
  case "${os}:${version}" in
    # The AUR carries the development branch as a package of its own.
    arch:HEAD) printf '%s-git\n' "${name}" ;;
    # Homebrew ships other versions as their own `name@version` package.
    macos:null | macos:latest | macos:HEAD | macos:) printf '%s\n' "${name}" ;;
    macos:*) printf '%s@%s\n' "${name}" "${version}" ;;
    *) printf '%s\n' "${name}" ;;
  esac
}

#######################################
# @description Install the package of an OS whose package manager takes a
# version in the package spec, the way every Linux distro and Termux do
# @arg $1 string YAML content of the package
# @arg $2 string Key of the OS in a tool's YAML
# @arg $3 string Package manager the spec is spelled for, as `dytoy::get_package_spec` takes it
# @arg $4 string Init system to enable the service of the package with, empty to skip
# @arg $5 string Function installing the spec, with the params after it
# @internal
#######################################
function __dytoy_install_spec_package {
  local yaml os manager init installer
  dybatpho::expect_args yaml os manager init installer -- "$@"
  local name version spec checker checked
  name=$(dytoy::get_field "${yaml}" "name")
  version=$(dytoy::get_field "${yaml}" "version")
  local -a params
  dytoy::get_params_into params "${yaml}"
  spec=$(dytoy::get_package_spec "${manager}" "${name}" "${version}") || return 1
  checker=$(dytoy::package_checker "${os}")
  checked=$(dytoy::checked_package_name "${os}" "${name}" "${version}")
  dytoy::install_package "${checked}" "${checker}" "${init}" "${yaml}" \
    "${installer}" "${spec}" ${params[@]+"${params[@]}"}
}

#######################################
# @description Install Gentoo package from the YAML file
# @arg $1 string YAML content
# @arg $2 string Init system of machine
#######################################
function dytoy::install_gentoo_package {
  local yaml init_system
  dybatpho::expect_args yaml init_system -- "$@"
  local repo url
  repo=$(dytoy::get_field "${yaml}" "repo")
  url=$(dytoy::get_field "${yaml}" "url")
  [[ "${repo}" == "null" ]] || package_manager::add_overlay "${repo}" "${url}" > /dev/null
  __dytoy_install_spec_package "${yaml}" gentoo portage "${init_system}" package_manager::install_via_portage
}

#######################################
# @description Install Arch package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_arch_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  __dytoy_install_spec_package "${yaml}" arch pacman systemd package_manager::install_via_pacman
}

#######################################
# @description Add an APT repository from the YAML file
# @arg $1 string YAML content
# @arg $2 string OS type, "ubuntu" or "termux"
#######################################
function dytoy::add_apt_repo {
  local yaml os
  dybatpho::expect_args yaml os -- "$@"
  local name repo
  name=$(dytoy::get_field "${yaml}" "name")
  repo=$(dytoy::get_field "${yaml}" "repo")
  [[ "${repo}" == "null" ]] && return

  local repo_name components suite key
  repo_name=$(dytoy::get_field "${yaml}" "repo_name")
  components=$(dytoy::get_field "${yaml}" "components")
  suite=$(dytoy::get_field "${yaml}" "suite")
  key=$(dytoy::get_field "${yaml}" "key")

  [[ "${repo_name}" == "null" ]] && repo_name=${name}
  if [[ "${suite}" == "null" ]]; then
    case "${os}" in
      ubuntu)
        suite=$(dybatpho::os_release UBUNTU_CODENAME) || suite=""
        ;;
      termux)
        suite=""
        ;;
      *) ;;
    esac
  fi
  local url="${repo//%v/${suite}}"
  package_manager::add_apt_repo "${repo_name}" "${url}" "${suite}" "${components}" "${key}"
  package_manager::sync_apt_repo
}

#######################################
# @description Install Ubuntu package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_ubuntu_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  dytoy::add_apt_repo "${yaml}" "ubuntu"
  __dytoy_install_spec_package "${yaml}" ubuntu apt systemd package_manager::install_via_apt
}

#######################################
# @description Install Alpine package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_alpine_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  __dytoy_install_spec_package "${yaml}" alpine apk openrc package_manager::install_via_apk
}

#######################################
# @description Install Termux package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_termux_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  __dytoy_install_spec_package "${yaml}" termux termux termux package_manager::install_via_termux
}

#######################################
# @description Install F-Droid app from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_fdroid_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  local name repo url
  name=$(dytoy::get_field "${yaml}" "name")
  local -a params
  dytoy::get_params_into params "${yaml}"
  repo=$(dytoy::get_field "${yaml}" "repo")
  url=$(dytoy::get_field "${yaml}" "url")
  [[ "${repo}" == "null" ]] || package_manager::add_fdroid_repo "${repo}" "${url}" > /dev/null

  dytoy::install_package "${name}" "fdroidcl" "" "${yaml}" \
    package_manager::install_via_fdroidcl "${name}" "${params[@]}"
}

#######################################
# @description Install Flatpak package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_flatpak_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  local name repo url
  name=$(dytoy::get_field "${yaml}" "name")
  local -a params
  dytoy::get_params_into params "${yaml}"
  repo=$(dytoy::get_field "${yaml}" "repo")
  url=$(dytoy::get_field "${yaml}" "url")
  [[ "${repo}" == "null" ]] || package_manager::add_flatpak_repo "${repo}" "${url}" > /dev/null

  dytoy::install_package "${name}" "flatpak" "" "${yaml}" \
    package_manager::install_via_flatpak "${name}" "${repo}" "${params[@]}"
}

#######################################
# @description Install MacOS package from the YAML file
# @arg $1 string YAML content
#######################################
function dytoy::install_macos_package {
  local yaml
  dybatpho::expect_args yaml -- "$@"
  local name type
  name=$(dytoy::get_field "${yaml}" "name")
  local -a params
  dytoy::get_params_into params "${yaml}"
  type=$(dytoy::get_field "${yaml}" "type")
  case "${type}" in
    store)
      dytoy::install_package "${name}" "mas" "" "${yaml}" \
        package_manager::install_via_mas "${name}" "${params[@]}"
      ;;
    download)
      local url
      url=$(dytoy::get_field "${yaml}" "url")
      dytoy::install_package "${name}" "dmg" "" "${yaml}" \
        package_manager::install_via_dmg "${name}" "${url}"
      ;;
    *)
      local version
      local -a brew_params=()
      version=$(dytoy::get_field "${yaml}" "version")
      if [[ "${type}" == "cask" ]]; then
        # Take over an app or font files left behind without a Caskroom
        # record, which brew otherwise refuses to overwrite.
        brew_params=("--cask" "--force")
      else
        brew_params=("--formula")
      fi
      [[ "${version}" != "HEAD" ]] || brew_params+=("--HEAD")
      name=$(dytoy::checked_package_name macos "${name}" "${version}")
      brew_params+=("${params[@]}")
      local repo
      repo=$(dytoy::get_field "${yaml}" "repo")
      [[ "${repo}" == "null" ]] || package_manager::add_brew_tap "${repo}" > /dev/null
      dytoy::install_package "${name}" "brew" "launchd" "${yaml}" \
        package_manager::install_via_brew "${name}" "${brew_params[@]}"
      ;;
  esac
}

#######################################
# @description Install Rosetta on MacOS
# @noargs
#######################################
function dytoy::install_macos_rosetta {
  if ! dybatpho::is file /usr/libexec/rosetta/runtime; then
    softwareupdate --install-rosetta --agree-to-license
  fi
}

#######################################
# @description Install the packages of the app store section of a tool, inside
# the hook of that section, once the store itself is installed
# @arg $1 string Name of tool
# @arg $2 string Section, `flatpak` or `fdroid`
# @arg $3 string Tool installing from the store, such as `fdroidcl`
# @internal
#######################################
function __dytoy_install_store_section {
  local name section store
  dybatpho::expect_args name section store -- "$@"
  local package
  local -a packages=()
  readarray -t packages < <(dytoy::get_yaml "${name}" "${section}.packages" || true)
  dybatpho::array_first packages &> /dev/null || return 0
  misc::install_tool "${store}"
  "package_manager::init_${section}"
  dytoy::run_section_hook "${name}" before "${section}"
  for package in ${packages[@]+"${packages[@]}"}; do
    "dytoy::install_${section}_package" "${package}"
  done
  dytoy::run_section_hook "${name}" after "${section}"
}

#######################################
# @description Install a tool with the package manager of this OS
# @arg $1 string Name of tool
# @env DYTOY_OS string Key of this OS in a tool's YAML, such as `gentoo`
# @env DYTOY_INIT_SYSTEM string Init system to enable services with
#######################################
# dyshellint disable=SC2310 the dytoy predicates are meant to be tested here
function dytoy::install_os_tool {
  local name
  dybatpho::expect_args name -- "$@"
  dytoy::install_dependencies "${name}"

  local package
  local -a packages=()
  dytoy::run_hook "${name}" before "${DYTOY_OS}"

  case "${DYTOY_OS}" in
    macos)
      local need_rosetta
      need_rosetta="$(dytoy::get_yaml "${name}" "need_rosetta")"
      dybatpho::is true "${need_rosetta}" && dytoy::install_macos_rosetta
      ;;
    termux) __dytoy_install_store_section "${name}" fdroid fdroidcl ;;
    *) __dytoy_install_store_section "${name}" flatpak flatpak ;;
  esac
  readarray -t packages < <(dytoy::get_yaml "${name}" "${DYTOY_OS}.packages" || true)
  for package in ${packages[@]+"${packages[@]}"}; do
    dytoy::is_package_for_release "${package}" || continue
    "dytoy::install_${DYTOY_OS}_package" "${package}" "${DYTOY_INIT_SYSTEM:-}"
  done

  dytoy::run_hook "${name}" after "${DYTOY_OS}"

  dybatpho::success "Installed os tool: ${name}"
}

#######################################
# @description Install a tool from a GitHub or GitLab release
# @arg $1 string Name of tool
# @arg $2 string "github" or "gitlab"
#######################################
# dyshellint disable=SC2310 the dytoy predicates are meant to be tested here
function dytoy::install_release {
  local name type
  dybatpho::expect_args name type -- "$@"
  local location host repo version release_asset artifact_host
  location="$(dybatpho::path_join "${HOME}" ".local" "bin")"
  location=$(dytoy::get_yaml_or "${name}" "location" "${location}")
  dytoy::is_installed_command "${name}" "${location}" && return
  dytoy::install_dependencies "${name}"
  dybatpho::debug "Download tool ${name} to ${location}"

  dybatpho::progress "Installing ${name}"
  dybatpho::ensure_dir "${location}" > /dev/null
  host=$(dytoy::get_yaml_or "${name}" "${type}.host" "${type}.com")
  dybatpho::debug "Host is ${host}"
  repo=$(dytoy::get_yaml "${name}" "${type}.repo")
  release_asset=$(dytoy::get_yaml "${name}" "${type}.release_asset")
  # The release source pins its own tag; the top-level `version` every method
  # reads is the fallback.
  version=$(dytoy::get_version "${name}" "${type}.version")
  [[ "${version}" == "latest" ]] && version=$(dytoy::get_version "${name}")

  if [[ "${version}" == "latest" ]]; then
    version=$(binary_download::get_latest_version "${host}" "${repo}")
    if dybatpho::string_is_blank "${version}"; then
      dybatpho::die "You're limited request to ${type} API"
    fi
  fi
  dybatpho::info "Using version ${version} for https://${host}/${repo}"
  release_asset=$(misc::replace_version "${version}" <<< "${release_asset}")
  dybatpho::info "Release asset is ${release_asset}"

  artifact_host=$(dytoy::get_yaml_or "${name}" "${type}.artifact_host" "")
  artifact_host=$(misc::replace_version "${version}" <<< "${artifact_host}")
  local url
  if ! dybatpho::string_is_blank "${artifact_host}"; then
    url="${artifact_host}/${release_asset}"
  elif [[ "${type}" == "github" ]]; then
    url="https://${host}/${repo}/releases/download/${version}/${release_asset}"
  else
    url="https://${host}/${repo}/-/releases/${version}/downloads/${release_asset}"
  fi

  local sha256_asset
  sha256_asset=$(dytoy::get_yaml_or "${name}" "${type}.sha256" "")
  if ! dybatpho::string_is_blank "${sha256_asset}"; then
    sha256_asset=$(misc::replace_version "${version}" <<< "${sha256_asset}")
    dybatpho::debug "SHA256 asset is ${sha256_asset}"
  fi

  binary_download::download_and_extract "${name}" "${location}" "${url}" "${version}" "${sha256_asset}"
}

#######################################
# @description Install a tool from a forge release
# @arg $1 string Name of tool
#######################################
# dyshellint disable=SC2310 the dytoy predicates are meant to be tested here
function dytoy::install_binary_tool {
  local name
  dybatpho::expect_args name -- "$@"

  local forge release_source
  for forge in github gitlab; do
    release_source="$(dytoy::get_yaml "${name}" "${forge}")"
    if [[ "${release_source}" != "null" ]]; then
      dytoy::install_release "${name}" "${forge}"
      return
    fi
  done
  dybatpho::die "No supported release source configured for ${name}"
}

#######################################
# @description Install a tool with mise
# @arg $1 string Name of tool
# @env DYTOY_OS string `termux` runs mise under proot
#######################################
# dyshellint disable=SC2310 the dytoy predicates are meant to be tested here
function dytoy::install_mise_tool {
  local name
  dybatpho::expect_args name -- "$@"
  dytoy::is_installed_command "${name}" && return
  dytoy::install_dependencies "${name}"

  local version
  version=$(dytoy::get_version "${name}")
  dytoy::run_hook "${name}" before "" "${version}"

  dybatpho::progress "Installing tool ${name}"
  # For some tools need specific backend
  local backend
  backend=$(dytoy::get_yaml_or "${name}" "backend" "${name}")
  local -a params
  readarray -t params < <(dytoy::get_yaml "${name}" "params" || true)

  local -a mise_command=(mise)
  if [[ "${DYTOY_OS:-}" == "termux" ]]; then
    local mise_bin
    mise_bin="$(dybatpho::path_join "${HOME}" ".local" "bin" "mise")"
    mise_command=(proot -b "${PREFIX:-}/etc/resolv.conf:/etc/resolv.conf"
      -b "${PREFIX:-}/etc/tls:/etc/ssl" "${mise_bin}")
  fi

  dybatpho::dry_run "${mise_command[@]}" use -g ${params[@]+"${params[@]}"} "${backend}@${version}"

  dytoy::run_hook "${name}" after "" "${version}"

  dybatpho::success "Installed mise tool: ${name}"
}

#######################################
# @description Install a tool by running the shell commands it declares
# @arg $1 string Name of tool
#######################################
# dyshellint disable=SC2310 the dytoy predicates are meant to be tested here
function dytoy::install_shell_tool {
  local name
  dybatpho::expect_args name -- "$@"
  dytoy::is_installed_command "${name}" && return
  dytoy::install_dependencies "${name}"

  dybatpho::progress "Installing tool ${name}"
  local content version script_path
  content="$(dytoy::get_yaml "${name}" "content")"
  version="$(dytoy::get_version "${name}")"
  dybatpho::create_temp script_path ".sh"
  # The content reads the version it should install from `$DYTOY_VERSION`.
  dytoy::create_script "${name}" "${script_path}" "${content}" "commands" "${version}"
  dytoy::run_script "${script_path}"
  dybatpho::success "Installed shell tool: ${name}"
}

#######################################
# @description Run one installer method over the selected tools
# @arg $1 string Method name, one of ${DYTOY_METHODS[@]}
# @env METHOD string Set to the method being run, read by dytoy::iterate
# @env DYTOY_OS string Key of this OS in a tool's YAML, empty when no package
#   manager is known for it
# @env DYTOY_OS_NAME string Name of this OS, as the os method reports it
# @env DYTOY_OSID string Chezmoi's ID of this OS, named when it has no package manager
#######################################
# dyshellint disable=SC2310 the dytoy predicates are meant to be tested here
function dytoy::run_method {
  dybatpho::expect_args METHOD -- "$@"
  case "${METHOD}" in
    os)
      if [[ -z "${DYTOY_OS:-}" ]]; then
        dybatpho::warn "No package manager is known for ${DYTOY_OSID:-this OS}, skip os tools"
        return 0
      fi
      # Without root, sudo or doas a Linux package manager runs unprivileged and fails.
      case "${DYTOY_OS}" in
        macos | termux) ;;
        *)
          if ! dybatpho::is_root && ! dybatpho::privilege_command > /dev/null; then
            dybatpho::warn "Neither root nor sudo or doas is available, skip os tools"
            return 0
          fi
          ;;
      esac
      if [[ "${TOOL}" == "@empty" ]]; then
        dybatpho::info "Distro of this machine is ${DYTOY_OS_NAME:-${DYTOY_OS}}."
      fi
      if dybatpho::is true "${SYNC_REPO:-}"; then
        "package_manager::init_${DYTOY_OS}"
      fi
      dytoy::iterate dytoy::install_os_tool
      ;;
    binary)
      dytoy::iterate dytoy::install_binary_tool
      ;;
    mise)
      misc::install_tool mise
      dytoy::iterate dytoy::install_mise_tool
      ;;
    shell)
      dytoy::iterate dytoy::install_shell_tool
      ;;
    *)
      dybatpho::die "Unknown installer method: ${METHOD}"
      ;;
  esac
}
