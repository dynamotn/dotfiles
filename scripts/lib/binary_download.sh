#!/usr/bin/env bash
# `name`, `type`, `DRY_RUN` and `LIST_CONTENTS` come from the caller's scope.
# dyshellint disable=SC2154 set by dytoy and dybatpho before these functions run
# @file binary_download.sh
# @brief Library `binary` to download a release asset and verify it
# @description Library `binary` to download a release asset from a forge and
# verify it. Requests go through the `network` module of dybatpho and the
# release metadata is read with the `json` module, so a caller only has to load
# `cli`. Archives are unpacked by the `archive` module, and the entries a tool
# wants are picked out of them by its `archive` specification.
dybatpho::load network json archive array

#######################################
# @description Infer a temp-file suffix from a download URL.
# @arg $1 string Download URL
# @stdout Matching archive/file suffix, or `.bin` as a fallback
#######################################
function __binary_download_temp_suffix {
  local url
  dybatpho::expect_args url -- "$@"
  case "${url}" in
    *.tar.gz | *.tar.gz\?* | *.tgz | *.tgz\?*)
      printf '.tar.gz\n'
      ;;
    *.tar.xz | *.tar.xz\?*)
      printf '.tar.xz\n'
      ;;
    *.tar.bz2 | *.tar.bz2\?* | *.tbz2 | *.tbz2\?* | *.tbz | *.tbz\?*)
      printf '.tar.bz2\n'
      ;;
    *.tar.zst | *.tar.zst\?*)
      printf '.tar.zst\n'
      ;;
    *.tar | *.tar\?*)
      printf '.tar\n'
      ;;
    *.zip | *.zip\?*)
      printf '.zip\n'
      ;;
    *.xz | *.xz\?*)
      printf '.xz\n'
      ;;
    *.bz2 | *.bz2\?*)
      printf '.bz2\n'
      ;;
    *.gz | *.gz\?*)
      printf '.gz\n'
      ;;
    *.zst | *.zst\?*)
      printf '.zst\n'
      ;;
    *)
      printf '.bin\n'
      ;;
  esac
}

#######################################
# @description Download a checksum file and verify the SHA256 of a downloaded asset.
# The checksum file must contain lines in 'sha256hash  filename' format.
# @arg $1 string Name of tool (for error messages)
# @arg $2 string Path to the already-downloaded asset file to verify
# @arg $3 string Full download URL of the release asset
# @arg $4 string Checksum filename (already version-substituted) in the same release
#######################################
function binary_download::verify_sha256 {
  local name temp_file url sha256_asset
  dybatpho::expect_args name temp_file url sha256_asset -- "$@"

  local sha256_url="${url%/*}/${sha256_asset}"
  dybatpho::progress "Verifying SHA256 for ${name}"

  local sha256_file
  dybatpho::create_temp sha256_file ".txt"
  dybatpho::curl_download "${sha256_url}" "${sha256_file}"

  local asset_name="${url##*/}"
  local expected_hash
  # Match 'hash  filename', 'hash  *filename' (sha256sum / shasum binary mode)
  # or 'hash  ./filename' (checksums generated from inside the release dir)
  expected_hash=$(grep -E "[[:space:]]\*?(\./)?${asset_name}\$" "${sha256_file}" | awk '{print $1}') || true

  # Fallback: per-asset files that contain only a bare hash (single entry)
  if dybatpho::string_is_blank "${expected_hash}"; then
    local line_count candidate
    # BSD `wc` pads the count with spaces, which the arithmetic test ignores.
    line_count=$(wc -l < "${sha256_file}")
    candidate=$(awk 'NR==1{print $1}' "${sha256_file}")
    if [[ "${line_count}" -le 1 && "${candidate}" =~ ^[0-9a-fA-F]{64}$ ]]; then
      # Single-hash per-asset file
      expected_hash="${candidate}"
    else
      dybatpho::die "SHA256 hash not found for ${asset_name} in ${sha256_url}"
    fi
  fi

  # A listed value that is no SHA256 digest can never match the asset, so it is
  # reported as the mismatch it is rather than as a malformed checksum spec.
  [[ "${expected_hash}" =~ ^[0-9a-fA-F]{64}$ ]] \
    || dybatpho::die "SHA256 mismatch for ${name}: expected ${expected_hash}, which is not a SHA256 digest"
  dybatpho::verify_checksum "${temp_file}" "sha256:${expected_hash}" \
    || dybatpho::die "SHA256 mismatch for ${name}"
  dybatpho::debug "SHA256 verified for ${name}: ${expected_hash}"
}

#######################################
# @description Get latest version of tool from GitHub or GitLab
# @arg $1 string Host of GitHub or GitLab
# @arg $2 string Repository of tool in format "owner/repo"
# @env GITHUB_TOKEN string Token for GitHub API
# @env GITLAB_TOKEN string Token for GitLab API
# @stdout Tag name of the latest release
#######################################
function binary_download::get_latest_version {
  local host repo
  dybatpho::expect_args host repo -- "$@"

  local temp_file
  dybatpho::create_temp temp_file ".txt"
  dybatpho::debug "Get version ${name:-tool} from https://${host}/${repo}"
  local type="${type:-}"
  if dybatpho::string_is_blank "${type}"; then
    if dybatpho::string_contains "${host}" "gitlab"; then
      type="gitlab"
    else
      type="github"
    fi
  fi
  local token="${GITHUB_TOKEN:-}"
  if [[ "${type}" == "gitlab" ]]; then
    token="${GITLAB_TOKEN:-}"
  fi
  # The token goes out of band, through a private curl config file, so it never
  # shows up in curl's command line (`ps`, `/proc/<pid>/cmdline`).
  # dyshellint disable=SC2034 read by dybatpho::curl_do through dynamic scoping
  local -a DYBATPHO_CURL_SECRET_HEADERS=(${token:+"Authorization: Bearer ${token}"})
  if [[ "${type}" == "github" ]]; then
    if dybatpho::is true "${DRY_RUN}"; then
      printf '%s\n' '{"tag_name": "v0.0.0"}' > "${temp_file}"
    else
      dybatpho::curl_do "https://api.${host}/repos/${repo}/releases/latest" "${temp_file}"
    fi
  elif [[ "${type}" == "gitlab" ]]; then
    if dybatpho::is true "${DRY_RUN}"; then
      printf '%s\n' '{"tag_name": "v0.0.0"}' > "${temp_file}"
    else
      local project
      project="$(dybatpho::url_encode "${repo}")"
      dybatpho::curl_do \
        "https://${host}/api/v4/projects/${project}/releases/permalink/latest" \
        "${temp_file}"
    fi
  fi
  local response
  response="$(< "${temp_file}")"
  # json_get works with either backend; `-o=props` was a yq-only flag.
  dybatpho::json_get "${response}" ".tag_name"
}

#######################################
# @description Render and run one hook of a tool, `hook.before` or `hook.after`
# @arg $1 string File name of command
# @arg $2 string Field of the hook in the tool specification
# @arg $3 string Label of the hook, used in the rendered script
# @arg $4 string Version of tool
#######################################
function __binary_download_run_hook {
  local name field label version
  dybatpho::expect_args name field label version -- "$@"
  local content script_path
  # A hook that cannot be read renders as an empty script, as it always has.
  content="$(dytoy::get_yaml "${name}" "${field}")" || true
  dybatpho::create_temp script_path ".sh"
  dytoy::create_script "${name}" "${script_path}" "${content}" "${label}" "${version}"
  dytoy::run_script "${script_path}"
}

#######################################
# @description Remove leading path components from a relative path.
# @arg $1 string Relative path
# @arg $2 number Number of leading components to drop
# @stdout Stripped relative path, or empty when nothing remains
#######################################
function __binary_download_strip_path {
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
function __binary_download_glob_matches {
  local root_dir pattern result_var
  dybatpho::expect_args root_dir pattern result_var -- "$@"
  local -n __binary_download_matches_ref="${result_var}"
  local search_pattern
  search_pattern="$(dybatpho::path_join "${root_dir}" "${pattern}")"
  mapfile -t __binary_download_matches_ref < <(compgen -G "${search_pattern}" || true)
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
function __binary_download_copy_selection {
  local extracted_root archive_pattern destination strip layout rename_target
  dybatpho::expect_args extracted_root archive_pattern destination strip layout rename_target -- "$@"

  dybatpho::ensure_dir "${destination}" > /dev/null
  if dybatpho::is true "${DRY_RUN}"; then
    # Separate words, so the rehearsal prints the command as it would run, with
    # each path quoted on its own; one string would be shown as a single word.
    local source_pattern
    source_pattern="$(dybatpho::path_join "${extracted_root}" "${archive_pattern}")"
    dybatpho::dry_run cp -R "${source_pattern}" "${destination}"
    return 0
  fi

  local -a matches=()
  __binary_download_glob_matches "${extracted_root}" "${archive_pattern}" matches
  dybatpho::array_first matches > /dev/null 2>&1 \
    || dybatpho::die "No archive entries matched pattern: ${archive_pattern}"

  local match relative_path stripped_path destination_path destination_dir
  for match in "${matches[@]}"; do
    relative_path="${match#"${extracted_root}"/}"
    stripped_path="$(__binary_download_strip_path "${relative_path}" "${strip}")"
    [[ -n "${stripped_path}" ]] || continue
    if [[ "${layout}" == "flat" ]]; then
      stripped_path="$(dybatpho::path_basename "${stripped_path}")"
    fi
    destination_path="$(dybatpho::path_join "${destination}" "${stripped_path}")"
    destination_dir="$(dybatpho::path_dirname "${destination_path}")"
    dybatpho::ensure_dir "${destination_dir}" > /dev/null
    cp -R "${match}" "${destination_path}"
  done

  [[ -n "${rename_target}" ]] || return 0
  local expected_name expected_path renamed_path
  expected_name="$(dybatpho::path_basename "${archive_pattern}")"
  expected_path="$(dybatpho::path_join "${destination}" "${expected_name}")"
  renamed_path="$(dybatpho::path_join "${destination}" "${rename_target}")"
  if [[ "${expected_name}" != "${rename_target}" ]] \
    && dybatpho::is exist "${expected_path}"; then
    dybatpho::dry_run mv "${expected_path}" "${renamed_path}"
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
function __binary_download_extract_archive {
  local name path location version layout rename_first
  dybatpho::expect_args name path location version layout rename_first -- "$@"
  if dybatpho::is true "${LIST_CONTENTS}"; then
    dybatpho::debug "Listing archive contents via dybatpho::archive_list"
    dybatpho::dry_run dybatpho::archive_list "${path}"
    return 0
  fi

  local temp_dir
  dybatpho::create_temp_dir temp_dir
  dybatpho::debug "Extracting archive to temp dir via dybatpho::archive_extract"
  dybatpho::dry_run dybatpho::archive_extract "${path}" "${temp_dir}"

  local archive_specs
  local -a archive=()
  # An unreadable specification selects nothing, as it always has.
  archive_specs="$(dytoy::get_yaml "${name}" "archive")" || true
  [[ -z "${archive_specs}" ]] || mapfile -t archive <<< "${archive_specs}"
  local rename_target=""
  dybatpho::is true "${rename_first}" && rename_target="${name}"
  local path_spec path_in_compress file_location strip
  for path_spec in "${archive[@]}"; do
    path_in_compress=$(dybatpho::json_get "${path_spec}" '.path')
    file_location=$(dybatpho::json_get "${path_spec}" '.location')
    [[ "${file_location}" != "null" ]] || file_location="${location}"
    strip=$(dybatpho::json_get "${path_spec}" '.strip')
    [[ "${strip}" != "null" ]] || strip=0
    path_in_compress="$(printf '%s\n' "${path_in_compress%%*( )}" | misc::replace_version "${version}")"
    dybatpho::debug "Selecting archive entries matching ${path_in_compress} into ${file_location}"
    __binary_download_copy_selection "${temp_dir}" "${path_in_compress}" "${file_location}" \
      "${strip}" "${layout}" "${rename_target}"
    # Only the first entry stands in for the command itself.
    rename_target=""
  done
}

#######################################
# @description Decompress a single-file archive, such as `.gz` or `.bz2`, into
# the command it holds
# @arg $1 string File name of command
# @arg $2 string Downloaded archive path, ending with its compression suffix
# @arg $3 string Destination directory
#######################################
function __binary_download_extract_single_file {
  local name path location
  dybatpho::expect_args name path location -- "$@"
  dybatpho::dry_run dybatpho::archive_extract "${path}" "${location}"
  # The codec writes the archive name without its suffix, which is rarely the
  # command name.
  local extracted_name
  extracted_name="$(dybatpho::path_basename "${path%.*}")"
  [[ "${extracted_name}" != "${name}" ]] || return 0
  local extracted_path target_path
  extracted_path="$(dybatpho::path_join "${location}" "${extracted_name}")"
  target_path="$(dybatpho::path_join "${location}" "${name}")"
  dybatpho::dry_run mv "${extracted_path}" "${target_path}"
}

#######################################
# @description Download tool from release file and extract it
# @arg $1 string File name of command
# @arg $2 string Location to download/extract file
# @arg $3 string URL of file
# @arg $4 string Version of tool
# @arg $5 string (optional) SHA256 checksum filename pattern (already version-substituted)
# @env LIST_CONTENTS boolean If false, grant execute permission extracted file
#######################################
function binary_download::download_and_extract {
  local name location url version
  dybatpho::expect_args name location url version -- "$@"
  local sha256_asset="${5:-}"
  local output_path temp_suffix temp_file
  output_path="$(dybatpho::path_join "${location}" "${name}")"
  temp_suffix="$(__binary_download_temp_suffix "${url}")"
  dybatpho::create_temp temp_file "${temp_suffix}"
  dybatpho::debug "Downloaded ${url} to ${temp_file}"
  dybatpho::curl_download "${url}" "${temp_file}"

  if ! dybatpho::string_is_blank "${sha256_asset}"; then
    binary_download::verify_sha256 "${name}" "${temp_file}" "${url}" "${sha256_asset}"
  fi

  __binary_download_run_hook "${name}" "hook.before" "before-hook" "${version}"

  # The temp file carries the archive suffix of the URL, without its query.
  case "${temp_file}" in
    # A tarball keeps the layout below its stripped prefix, and its first
    # entry stands in for the command.
    *.tar.gz | *.tar.xz | *.tar.bz2 | *.tar.zst | *.tar)
      __binary_download_extract_archive "${name}" "${temp_file}" "${location}" "${version}" "tree" true
      ;;
    *.zip)
      __binary_download_extract_archive "${name}" "${temp_file}" "${location}" "${version}" "flat" false
      ;;
    *.gz | *.bz2 | *.xz | *.zst)
      __binary_download_extract_single_file "${name}" "${temp_file}" "${location}"
      ;;
    *)
      dybatpho::dry_run mv "${temp_file}" "${output_path}"
      ;;
  esac
  if ! dybatpho::is true "${LIST_CONTENTS}"; then
    dybatpho::dry_run chmod +x "${output_path}"
  fi

  __binary_download_run_hook "${name}" "hook.after" "after-hook" "${version}"

  dybatpho::success "Installed binary tool: ${name}"
}
