#!/usr/bin/env bash
# shellcheck disable=2154,2155

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
  if ((strip == 0)); then
    printf '%s\n' "${relative_path}"
    return 0
  fi
  printf '%s\n' "${relative_path}" \
    | awk -F/ -v n="${strip}" 'NF>n{for(i=n+1;i<=NF;i++) printf "%s%s", $i, (i<NF?"/":"")} END{if (NF>n) printf "\n"}'
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
# @description Copy selected tar entries from a temp extraction directory.
# @arg $1 string Extracted archive root
# @arg $2 string Archive member pattern
# @arg $3 string Destination directory
# @arg $4 number Strip-components count
# @arg $5 string Optional rename target for the first extracted entry
#######################################
function __compressed_copy_tar_selection {
  local extracted_root archive_pattern destination strip rename_target
  dybatpho::expect_args extracted_root archive_pattern destination strip rename_target -- "$@"
  local expected_name
  expected_name="$(dybatpho::path_basename "${archive_pattern}")"

  mkdir -p "${destination}"
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
    relative_path="${match#${extracted_root}/}"
    stripped_path="$(__compressed_strip_path "${relative_path}" "${strip}")"
    [[ -n "${stripped_path}" ]] || continue
    destination_path="$(dybatpho::path_join "${destination}" "${stripped_path}")"
    mkdir -p "$(dybatpho::path_dirname "${destination_path}")"
    cp -R "${match}" "${destination_path}"
  done

  if [[ -n "${rename_target}" && "${expected_name}" != "${rename_target}" ]] && dybatpho::is exist "$(dybatpho::path_join "${destination}" "${expected_name}")"; then
    dybatpho::dry_run mv \
      "$(dybatpho::path_join "${destination}" "${expected_name}")" \
      "$(dybatpho::path_join "${destination}" "${rename_target}")"
  fi
}

#######################################
# @description Copy selected zip entries from a temp extraction directory.
# @arg $1 string Extracted archive root
# @arg $2 string Archive member pattern
# @arg $3 string Destination directory
# @arg $4 number Strip-components count
#######################################
function __compressed_copy_zip_selection {
  local extracted_root archive_pattern destination strip
  dybatpho::expect_args extracted_root archive_pattern destination strip -- "$@"
  mkdir -p "${destination}"
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
    relative_path="${match#${extracted_root}/}"
    stripped_path="$(__compressed_strip_path "${relative_path}" "${strip}")"
    [[ -n "${stripped_path}" ]] || continue
    destination_path="$(dybatpho::path_join "${destination}" "$(dybatpho::path_basename "${stripped_path}")")"
    cp -R "${match}" "${destination_path}"
  done
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
# @description Extract from tar compressed release file
# @arg $1 string Compressed file location to extract
# @arg $2 string Location to extract
# @arg $3 string URL of file when downloading
# @arg $4 string File name of command
# @arg $4 string Version of tool
# @env LIST_CONTENTS boolean If true, list contents of archive instead of extracting
#######################################
function compressed:extract_tar {
  local name path location url version
  dybatpho::expect_args name path location url version -- "$@"
  if dybatpho::is true "$LIST_CONTENTS"; then
    dybatpho::debug "Listing archive contents via dybatpho::archive_list"
    dybatpho::dry_run dybatpho::archive_list "$path"
  else
    local temp_dir
    dybatpho::create_temp temp_dir ""
    dybatpho::debug "Extracting archive to temp dir via dybatpho::archive_extract"
    dybatpho::dry_run dybatpho::archive_extract "$path" "$temp_dir"

    readarray archive < <(dytoy::get_yaml "$name" "archive")
    local is_first_file=true
    for path_spec in "${archive[@]}"; do
      local path_in_compress=$(echo "$path_spec" | yq e -o=j -I=0 -r '.path')
      local file_location=$(echo "$path_spec" | yq e -o=j -I=0 -r '.location')
      if [ "$file_location" = "null" ]; then
        file_location="$location"
      fi
      local strip=$(echo "$path_spec" | yq e -o=j -I=0 -r '.strip')
      if [ "$strip" = "null" ]; then
        strip=0
      fi
      path_in_compress="$(echo "${path_in_compress%%*( )}" | misc::replace_version "$version")"
      dybatpho::debug "Selecting tar entries matching ${path_in_compress} into ${file_location}"
      if dybatpho::is true "$is_first_file"; then
        __compressed_copy_tar_selection "$temp_dir" "$path_in_compress" "$file_location" "$strip" "$name"
        is_first_file=false
      else
        __compressed_copy_tar_selection "$temp_dir" "$path_in_compress" "$file_location" "$strip" ""
      fi

    done
  fi
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
  if dybatpho::is true "$LIST_CONTENTS"; then
    dybatpho::debug "Listing archive contents via dybatpho::archive_list"
    dybatpho::dry_run dybatpho::archive_list "$path"
  else
    local temp_dir
    dybatpho::create_temp temp_dir ""
    dybatpho::debug "Extracting archive to temp dir via dybatpho::archive_extract"
    dybatpho::dry_run dybatpho::archive_extract "$path" "$temp_dir"

    readarray archive < <(dytoy::get_yaml "$name" "archive")
    for path_spec in "${archive[@]}"; do
      local path_in_compress=$(echo "$path_spec" | yq e -o=j -I=0 -r '.path')
      local file_location=$(echo "$path_spec" | yq e -o=j -I=0 -r '.location')
      if [ "$file_location" = "null" ]; then
        file_location="$location"
      fi
      local strip=$(echo "$path_spec" | yq e -o=j -I=0 -r '.strip')
      if [ "$strip" = "null" ]; then
        strip=0
      fi
      path_in_compress="$(echo "${path_in_compress%%*( )}" | misc::replace_version "$version")"
      dybatpho::debug "Selecting zip entries matching ${path_in_compress} into ${file_location}"
      __compressed_copy_zip_selection "$temp_dir" "$path_in_compress" "$file_location" "$strip"
    done
  fi
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
