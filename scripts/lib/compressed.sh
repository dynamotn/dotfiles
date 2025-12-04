#!/usr/bin/env bash
# shellcheck disable=2154,2155

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
  local param=("--warning=no-unknown-keyword")
  param+=("--wildcards")
  if dybatpho::is true "$LIST_CONTENTS"; then
    param+=("-vt")
  else
    param+=("-x")
  fi
  if [[ "$url" =~ \.(tar\.gz|tgz)$ ]]; then
    param+=("-z")
  elif [[ "$url" =~ \.(tar\.xz|xz)$ ]]; then
    param+=("-J")
  elif [[ "$url" =~ \.(tar\.bz2|tbz2|tbz)$ ]]; then
    param+=("-j")
  elif [[ "$url" =~ \.(tar\.zst)$ ]]; then
    param+=("--zstd")
  fi

  param+=("-f $path")
  dybatpho::debug "File $(file "$path")"
  if dybatpho::is true "$LIST_CONTENTS"; then
    dybatpho::debug "List with params: ${param[*]}"
    # shellcheck disable=2145
    dybatpho::dry_run eval "tar ${param[@]} >&2"
  else
    readarray archive < <(dytoy::get_yaml "$name" "archive")
    local is_first_file=true
    for path_spec in "${archive[@]}"; do
      local extract_param=("${param[@]}")
      local path_in_compress=$(echo "$path_spec" | yq e -o=j -I=0 -r '.path')
      local file_location=$(echo "$path_spec" | yq e -o=j -I=0 -r '.location')
      if [ "$file_location" = "null" ]; then
        file_location="$location"
      fi
      extract_param+=("-C $file_location")
      mkdir -p "$file_location"
      local strip=$(echo "$path_spec" | yq e -o=j -I=0 -r '.strip')
      if [ "$strip" != "null" ]; then
        extract_param+=("--strip-components=$strip")
      fi
      extract_param+=("$(echo "${path_in_compress%%*( )}" | misc::replace_version "$version")")
      dybatpho::debug "Extracting with params: ${extract_param[*]}"
      # shellcheck disable=2145
      dybatpho::dry_run eval "tar ${extract_param[@]} >&2"

      # Move first file to command name
      if dybatpho::is true "$is_first_file"; then
        is_first_file=false
        if [[ ${path_in_compress##*/} != "$name" ]]; then
          dybatpho::dry_run mv "${file_location}/${path_in_compress##*/}" "${file_location}/${name}"
        fi
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
    local param=("-Zl $path")
    # shellcheck disable=2145
    dybatpho::dry_run eval "unzip ${param[@]} >&2"
  else
    readarray archive < <(dytoy::get_yaml "$name" "archive")
    for path_spec in "${archive[@]}"; do
      local param=("-qqoj $path")
      local path_in_compress=$(echo "$path_spec" | yq e -o=j -I=0 -r '.path')
      local file_location=$(echo "$path_spec" | yq e -o=j -I=0 -r '.location')
      if [ "$file_location" = "null" ]; then
        param+=("-d $location")
      else
        param+=("-d $file_location")
      fi
      param+=("$(echo "${path_in_compress%%*( )}" | misc::replace_version "$version")")
      dybatpho::debug "Extracting with params: ${param[*]}"
      # shellcheck disable=2145
      dybatpho::dry_run eval "unzip ${param[@]} >&2"
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
  bzip2 -cd "$path" > "${location}/${name}"
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
  gzip -cd "$path" > "${location}/${name}"
}
