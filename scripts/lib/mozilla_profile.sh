#!/usr/bin/env bash
# @file mozilla_profile.sh
# @brief Shared machinery of the Gecko profile managers, `dyfox` and `dybird`
# @description Firefox/Zen and Thunderbird/Betterbird keep the same shape of
# profile tree, and both tools do the same two things to it: copy the live data
# into the dotfiles, or throw the live data away and lay it down again from the
# dotfiles. What differs between them is only the list of files each one cares
# about, so that list is all their entry points still hold.
#
# Every function reads the profile layout from the variables below, which the
# entry point sets once from its chezmoi template.
#
# @env MOZILLA_APP_NAME string Name of the application, as the user configured it
# @env MOZILLA_APP_KIND string What the application is, for the opening log line
# @env MOZILLA_PROCESS string Process to look for before touching any data
# @env MOZILLA_PROFILE_ROOT string Folder holding the live profiles
# @env MOZILLA_TEMPLATE_ROOT string Folder holding the `prefs` chezmoi templates
# @env MOZILLA_PROFILES array Profiles this installation knows about
# @env PROFILE string Profile the user selected, empty for all of them

# @env MOZILLA_FAILED_STORES number Folders `mozilla::store` could not encrypt
MOZILLA_FAILED_STORES=0

#######################################
# @description Folder of the live data of a profile
# @arg $1 string Profile
# @stdout Path of the profile folder
#######################################
function mozilla::profile_dir {
  local profile
  dybatpho::expect_args profile -- "$@"
  dybatpho::path_join "${MOZILLA_PROFILE_ROOT}" "${profile}"
}

#######################################
# @description Folder of the `prefs` chezmoi templates of a profile
# @arg $1 string Profile
# @stdout Path of the template folder
#######################################
function mozilla::prefs_template_dir {
  local profile
  dybatpho::expect_args profile -- "$@"
  dybatpho::path_join "${MOZILLA_TEMPLATE_ROOT}" "${profile}"
}

#######################################
# @description Check a profile against the one the user selected
# @arg $1 string Profile
# @exitcode 1 The user selected another profile
#######################################
function mozilla::selected {
  local profile
  dybatpho::expect_args profile -- "$@"
  [[ -z "${PROFILE}" || "${PROFILE}" == "${profile}" ]]
}

#######################################
# @description Check the value of `--profile` against the known profiles
# @arg $1 string Value to validate, empty means every profile
# @exitcode 1 No profile goes by that name
#######################################
function mozilla::validate_profile {
  local value
  dybatpho::expect_args value -- "$@"
  [[ -z "${value}" ]] && return 0
  dybatpho::array_contains MOZILLA_PROFILES "${value}" && return 0

  local profile list=""
  for profile in "${MOZILLA_PROFILES[@]}"; do
    list+="'${profile}' "
  done
  dybatpho::error "Profile must be one of this list: ${list}"
  return 1
}

#######################################
# @description Run a callback once per profile the user selected
# @arg $1 string Name of a function taking the profile as its only argument
#######################################
function mozilla::for_each_profile {
  local callback
  dybatpho::expect_args callback -- "$@"
  local profile
  for profile in "${MOZILLA_PROFILES[@]}"; do
    if mozilla::selected "${profile}"; then
      "${callback}" "${profile}"
    else
      dybatpho::debug "${PROFILE}"
    fi
  done
}

#######################################
# @description Replace the live data of a profile with the dotfiles copy
# @arg $1 string Profile
#######################################
function mozilla::refresh_profile {
  local profile
  dybatpho::expect_args profile -- "$@"
  local profile_dir
  profile_dir="$(mozilla::profile_dir "${profile}")"
  dybatpho::dry_run rm -rf "${profile_dir}"
  # The live data is already gone at this point, so a failure here is fatal
  # rather than something to walk past.
  dybatpho::dry_run chezmoi apply "${profile_dir}" --force \
    || dybatpho::die "Cannot lay ${profile_dir} down again from the dotfiles, its live data is gone"
}

#######################################
# @description Copy the preferences matching some patterns into a template
# @arg $1 string Template file to write
# @arg $2 string `prefs.js` of the profile
# @arg $@ string Patterns to look for, in the order they are written
#######################################
function mozilla::extract_prefs {
  local output prefs_file
  dybatpho::expect_args output prefs_file -- "$@"
  shift 2

  # Collected apart from the template: writing the matches straight into it
  # would empty a good template as soon as one pattern stops matching, and
  # `prefs.js` drops a preference as soon as it holds its default value.
  local temp_file pattern
  dybatpho::create_temp temp_file ".js"
  for pattern in "$@"; do
    grep "${pattern}" "${prefs_file}" >> "${temp_file}" || true
  done

  if [[ ! -s "${temp_file}" ]]; then
    dybatpho::warn "No preference of ${prefs_file} matches ${*}, keeping ${output} as it is"
    return 0
  fi
  dybatpho::dry_run cp "${temp_file}" "${output}"
}

#######################################
# @description Track files of a folder in the dotfiles as they are
# @arg $1 string Folder holding the files
# @arg $@ string Names of the files, relative to that folder
#######################################
function mozilla::add {
  local folder
  dybatpho::expect_args folder -- "$@"
  shift

  local name path
  for name in "$@"; do
    path="$(dybatpho::path_join "${folder}" "${name}")"
    # Several of these files only exist for some profiles or some versions of
    # the application, and chezmoi reports a missing path as an error. Asking
    # first keeps a normal run free of errors that mean nothing.
    if ! compgen -G "${path}" > /dev/null; then
      dybatpho::debug "No file at ${path}, nothing to track"
      continue
    fi
    dybatpho::dry_run chezmoi add "${path}" --create || true
  done
}

#######################################
# @description Track files of a folder in the dotfiles, encrypted unless the
#   profile is the public one
# @arg $1 string Profile
# @arg $2 string Folder holding the files
# @arg $@ string Names of the files, relative to that folder
#######################################
function mozilla::store {
  local profile folder
  dybatpho::expect_args profile folder -- "$@"
  shift 2
  (($#)) || return 0

  if [[ "${profile}" == "public" ]]; then
    mozilla::add "${folder}" "$@"
  elif ! dybatpho::dry_run chezmoi-dycrypt encrypt -i "${profile}" -f "${folder}" -a "create" "$@"; then
    # One call now carries a whole folder, so swallowing its failure would lose
    # every file of that folder without a word. The run carries on and says so
    # at the end instead.
    dybatpho::warn "Cannot encrypt ${#} file(s) of ${folder}"
    MOZILLA_FAILED_STORES=$((MOZILLA_FAILED_STORES + 1))
  fi
}

#######################################
# @description Encrypt every file under a folder into the dotfiles
# @arg $1 string Profile
# @arg $2 string Folder to walk, skipped when it does not exist
# @arg $@ string Extra `find` predicates narrowing the files to take
# @note The files are handed over one folder at a time, because
#   `chezmoi-dycrypt encrypt` takes the folder once and the file names after
#   it. One process per folder also replaces the one process per file the
#   `xargs` this used to run would have paid for.
#######################################
function mozilla::store_tree {
  local profile root
  dybatpho::expect_args profile root -- "$@"
  shift 2

  if ! dybatpho::is dir "${root}"; then
    dybatpho::debug "Folder ${root} does not exist, nothing to encrypt"
    return 0
  fi

  local -a files=()
  # Sorted so that the files of one folder arrive together, and null separated
  # so that a space in a profile path cannot split one name into two.
  mapfile -d '' -t files < <(command find "${root}" -type f "$@" -print0 | sort -z)
  ((${#files[@]})) || return 0

  local file folder current=""
  local -a batch=()
  for file in "${files[@]}"; do
    folder="$(dybatpho::path_dirname "${file}")"
    if [[ "${folder}" != "${current}" ]]; then
      mozilla::store "${profile}" "${current}" "${batch[@]}"
      current="${folder}"
      batch=()
    fi
    batch+=("$(dybatpho::path_basename "${file}")")
  done
  mozilla::store "${profile}" "${current}" "${batch[@]}"
}

#######################################
# @description Run the tool: refresh the live data, or update the dotfiles
# @arg $1 string Name of the function updating the dotfiles of one profile
# @env REFRESH string Refresh the live data instead of updating the dotfiles
#######################################
function mozilla::run {
  local update_profile
  dybatpho::expect_args update_profile -- "$@"
  dybatpho::info "Your ${MOZILLA_APP_KIND} in chezmoi settings is ${MOZILLA_APP_NAME}"

  # Copying a profile out from under a running application reads half written
  # databases, so this is where the tool stops.
  if pgrep -f "${MOZILLA_PROCESS}" > /dev/null; then
    dybatpho::die "${MOZILLA_APP_NAME} is running"
  elif dybatpho::is true "${REFRESH}"; then
    dybatpho::header "Refresh from scratch ${MOZILLA_APP_NAME} settings"
    mozilla::for_each_profile mozilla::refresh_profile
    dybatpho::success "Refresh from scratch ${MOZILLA_APP_NAME} settings"
  else
    dybatpho::header "Update ${MOZILLA_APP_NAME} settings"
    mozilla::for_each_profile "${update_profile}"
    ((MOZILLA_FAILED_STORES == 0)) \
      || dybatpho::die "${MOZILLA_FAILED_STORES} folder(s) could not be encrypted, the dotfiles are not up to date"
    dybatpho::success "Update ${MOZILLA_APP_NAME} settings"
  fi
}
