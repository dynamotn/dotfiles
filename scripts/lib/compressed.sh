#!/usr/bin/env bash
# shellcheck disable=2154,2155
# @file compressed.sh
# @brief Library `compressed` to extract downloaded release archives
# @description Library `compressed` to extract downloaded release archives.
# Listing and extracting go through the `archive` module of dybatpho, and the
# archive specification of a tool is read with the `json` module.
dybatpho::load archive array json

#######################################
# @description Remove leading path components from a relative path.
# @arg $1 string Relative path
# @arg $2 number Number of leading components to drop
# @stdout Stripped relative path, or empty when nothing remains
#######################################
function __compressed_strip_path {
  local relative_path strip
  dybatpho::expect_args relative_path strip -- "$@"
  [[ "${strip}" =~ ^[0-9]+$ ]] || dybatpho::die "Invalid strip count: ${strip}"
  local index
  for ((index = 0; index < strip; index++)); do
    # Nothing is left to print once the last component would be dropped.
    [[ "${relative_path}" == */* ]] || return 0
    relative_path="${relative_path#*/}"
  done
  printf '%s\n' "${relative_path}"
}

#######################################
# @description Expand a relative glob pattern inside an extracted archive root.
# @arg $1 string Extracted archive root
# @arg $2 string Relative glob pattern
# @arg $3 string Name of array variable receiving matches
#######################################
function __compressed_glob_matches {
  local root_dir pattern result_var
  dybatpho::expect_args root_dir pattern result_var -- "$@"
  local -n __compressed_matches_ref="${result_var}"
  local search_pattern
  search_pattern="$(dybatpho::path_join "$root_dir" "$pattern")"
  mapfile -t __compressed_matches_ref < <(compgen -G "${search_pattern}" || true)
}

#######################################
# @description Copy selected archive entries from a temp extraction directory.
# @arg $1 string Extracted archive root
# @arg $2 string Archive member pattern
# @arg $3 string Destination directory
# @arg $4 number Strip-components count
# @arg $5 string Layout of the copy, `tree` to keep the stripped path, `flat` to drop it
# @arg $6 string Optional rename target for the extracted entry
# @env DRY_RUN boolean If true, show the copy command instead of running it
#######################################
function __compressed_copy_selection {
  local extracted_root archive_pattern destination strip layout rename_target
  dybatpho::expect_args extracted_root archive_pattern destination strip layout rename_target -- "$@"

  dybatpho::ensure_dir "${destination}" > /dev/null
  if dybatpho::is true "${DRY_RUN}"; then
    dybatpho::dry_run "cp -R \"$(dybatpho::path_join "${extracted_root}" "${archive_pattern}")\" \"${destination}\""
    return 0
  fi

  local matches=()
  __compressed_glob_matches "${extracted_root}" "${archive_pattern}" matches
  dybatpho::array_first matches > /dev/null 2>&1 \
    || dybatpho::die "No archive entries matched pattern: ${archive_pattern}"

  local match relative_path stripped_path destination_path
  for match in "${matches[@]}"; do
    relative_path="${match#"${extracted_root}"/}"
    stripped_path="$(__compressed_strip_path "${relative_path}" "${strip}")"
    [[ -n "${stripped_path}" ]] || continue
    if [[ "${layout}" == "flat" ]]; then
      stripped_path="$(dybatpho::path_basename "${stripped_path}")"
    fi
    destination_path="$(dybatpho::path_join "${destination}" "${stripped_path}")"
    dybatpho::ensure_dir "$(dybatpho::path_dirname "${destination_path}")" > /dev/null
    cp -R "${match}" "${destination_path}"
  done

  [[ -n "${rename_target}" ]] || return 0
  local expected_name
  expected_name="$(dybatpho::path_basename "${archive_pattern}")"
  if [[ "${expected_name}" != "${rename_target}" ]] && dybatpho::is exist "$(dybatpho::path_join "${destination}" "${expected_name}")"; then
    dybatpho::dry_run mv \
      "$(dybatpho::path_join "${destination}" "${expected_name}")" \
      "$(dybatpho::path_join "${destination}" "${rename_target}")"
  fi
}

#######################################
# @description Extract a single-file compressed archive via dybatpho::archive_extract.
# @arg $1 string File name of command
# @arg $2 string Downloaded archive path
# @arg $3 string Destination directory
# @arg $4 string Expected archive suffix, including leading dot
#######################################
function __compressed_extract_single_file {
  local name path location archive_suffix
  dybatpho::expect_args name path location archive_suffix -- "$@"
  local target_path archive_path extracted_name
  target_path="$(dybatpho::path_join "$location" "$name")"
  archive_path="$path"
  if [[ "$archive_path" != *"${archive_suffix}" ]]; then
    archive_path="${path}${archive_suffix}"
    dybatpho::dry_run cp "$path" "$archive_path"
  fi
  dybatpho::dry_run dybatpho::archive_extract "$archive_path" "$location"
  extracted_name="$(dybatpho::path_basename "$archive_path" "$archive_suffix")"
  if [[ "${extracted_name}" != "$name" ]]; then
    dybatpho::dry_run mv \
      "$(dybatpho::path_join "$location" "${extracted_name}")" \
      "$target_path"
  fi
}

#######################################
# @description Extract entries described by the `archive` field of a tool.
# @arg $1 string File name of command
# @arg $2 string Compressed file location to extract
# @arg $3 string Default location to extract
# @arg $4 string Version of tool
# @arg $5 string Layout of the copy, `tree` to keep the stripped path, `flat` to drop it
# @arg $6 boolean If true, rename the first extracted entry to the command name
# @env LIST_CONTENTS boolean If true, list contents of archive instead of extracting
#######################################
function __compressed_extract_archive {
  local name path location version layout rename_first
  dybatpho::expect_args name path location version layout rename_first -- "$@"
  if dybatpho::is true "$LIST_CONTENTS"; then
    dybatpho::debug "Listing archive contents via dybatpho::archive_list"
    dybatpho::dry_run dybatpho::archive_list "$path"
    return 0
  fi

  local temp_dir
  dybatpho::create_temp_dir temp_dir
  dybatpho::debug "Extracting archive to temp dir via dybatpho::archive_extract"
  dybatpho::dry_run dybatpho::archive_extract "$path" "$temp_dir"

  readarray -t archive < <(dytoy::get_yaml "$name" "archive")
  local rename_target=""
  dybatpho::is true "$rename_first" && rename_target="$name"
  local path_spec path_in_compress file_location strip
  for path_spec in "${archive[@]}"; do
    path_in_compress=$(dybatpho::json_get "$path_spec" '.path')
    file_location=$(dybatpho::json_get "$path_spec" '.location')
    [[ "$file_location" != "null" ]] || file_location="$location"
    strip=$(dybatpho::json_get "$path_spec" '.strip')
    [[ "$strip" != "null" ]] || strip=0
    path_in_compress="$(echo "${path_in_compress%%*( )}" | misc::replace_version "$version")"
    dybatpho::debug "Selecting archive entries matching ${path_in_compress} into ${file_location}"
    __compressed_copy_selection "$temp_dir" "$path_in_compress" "$file_location" "$strip" "$layout" "$rename_target"
    # Only the first entry stands in for the command itself.
    rename_target=""
  done
}

#######################################
# @description Extract from tar compressed release file
# @arg $1 string File name of command
# @arg $2 string Compressed file location to extract
# @arg $3 string Location to extract
# @arg $4 string URL of file when downloading
# @arg $5 string Version of tool
# @env LIST_CONTENTS boolean If true, list contents of archive instead of extracting
#######################################
function compressed:extract_tar {
  # shellcheck disable=SC2034
  local name path location url version
  dybatpho::expect_args name path location url version -- "$@"
  __compressed_extract_archive "$name" "$path" "$location" "$version" "tree" true
}

#######################################
# @description Extract from zip compressed release file
# @arg $1 string File name of command
# @arg $2 string Compressed file location to extract
# @arg $3 string Location to extract
# @arg $4 string Version of tool
# @env LIST_CONTENTS boolean If true, list contents of archive instead of extracting
#######################################
function compressed:extract_zip {
  local name path location version
  dybatpho::expect_args name path location version -- "$@"
  __compressed_extract_archive "$name" "$path" "$location" "$version" "flat" false
}

#######################################
# @description Extract from bzip2 compressed release file
# @arg $1 string File name of command
# @arg $2 string Compressed file location to extract
# @arg $3 string Location to extract
#######################################
function compressed:extract_bzip2 {
  local name path location
  dybatpho::expect_args name path location -- "$@"
  __compressed_extract_single_file "$name" "$path" "$location" ".bz2"
}

#######################################
# @description Extract from gzip compressed release file
# @arg $1 string File name of command
# @arg $2 string Compressed file location to extract
# @arg $3 string Location to extract
#######################################
function compressed:extract_gzip {
  local name path location
  dybatpho::expect_args name path location -- "$@"
  __compressed_extract_single_file "$name" "$path" "$location" ".gz"
}
