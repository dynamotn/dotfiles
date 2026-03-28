#!/usr/bin/env bash
# shellcheck disable=2154,2155

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
# @description Compute SHA256 of a file, works on both Linux and macOS.
# @arg $1 string Path to the file
# @stdout hex digest string
#######################################
function __binary_sha256sum {
  local file
  dybatpho::expect_args file -- "$@"
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "${file}" | awk '{print $1}'
  else
    shasum -a 256 "${file}" | awk '{print $1}'
  fi
}

#######################################
# @description Download a checksum file and verify the SHA256 of a downloaded asset.
# The checksum file must contain lines in 'sha256hash  filename' format.
# @arg $1 string Name of tool (for error messages)
# @arg $2 string Path to the already-downloaded asset file to verify
# @arg $3 string Full download URL of the release asset
# @arg $4 string Checksum filename (already version-substituted) in the same release
#######################################
function binary::verify_sha256 {
  local name temp_file url sha256_asset
  dybatpho::expect_args name temp_file url sha256_asset -- "$@"

  local sha256_url="${url%/*}/${sha256_asset}"
  dybatpho::progress "Verifying SHA256 for ${name}"

  dybatpho::create_temp sha256_file ".txt"
  dybatpho::curl_download "${sha256_url}" "${sha256_file}"

  local asset_name="${url##*/}"
  local expected_hash
  # Match 'hash  filename' or 'hash  *filename' (sha256sum / shasum binary mode)
  expected_hash=$(grep -E "[[:space:]]\*?${asset_name}\$" "${sha256_file}" | awk '{print $1}') || true

  # Fallback: per-asset files that contain only a bare hash (single entry)
  if dybatpho::string_is_blank "${expected_hash}"; then
    local line_count candidate
    line_count=$(wc -l < "${sha256_file}" | tr -d ' ')
    candidate=$(awk 'NR==1{print $1}' "${sha256_file}")
    if [[ "${line_count}" -le 1 && "${candidate}" =~ ^[0-9a-fA-F]{64}$ ]]; then
      # Single-hash per-asset file
      expected_hash="${candidate}"
    else
      # Multi-entry file but asset not covered (e.g. macOS absent from Linux-only checksums.txt)
      dybatpho::warn "SHA256 hash not found for ${asset_name} in ${sha256_url}, skipping verification"
      return 0
    fi
  fi

  local actual_hash
  actual_hash=$(__binary_sha256sum "${temp_file}")

  if [[ "${expected_hash}" != "${actual_hash}" ]]; then
    dybatpho::die "SHA256 mismatch for ${name}: expected ${expected_hash}, got ${actual_hash}"
  fi
  dybatpho::debug "SHA256 verified for ${name}: ${actual_hash}"
}


# @arg $1 string Host of GitHub or GitLab
# @arg $2 string Repository of tool in format "owner/repo"
# @env GITHUB_TOKEN string Token for GitHub API
# @env GITLAB_TOKEN string Token for GitLab API
#######################################
function binary::get_latest_version {
  local host repo
  dybatpho::expect_args host repo -- "$@"
  dybatpho::create_temp temp_file ".txt"
  dybatpho::debug "Get version ${name} from https://${host}/${repo}"
  if [ "$type" = "github" ]; then
    local param=()
    if [ "${GITHUB_TOKEN:-x}" != "x" ]; then
      param=("-H" "'Authorization: Bearer ${GITHUB_TOKEN}'")
    fi
    dybatpho::curl_do "https://api.${host}/repos/${repo}/releases/latest" "$temp_file" "${param[@]}"
    grep -Po "tag_name\": \"(\K.*)(?=\",)" "$temp_file"
  elif [ "$type" = "gitlab" ]; then
    local param=()
    if [ "${GITLAB_TOKEN:-x}" != "x" ]; then
      param=("-H" "'Authorization: Bearer ${GITLAB_TOKEN}'")
    fi
    dybatpho::curl_do "https://${host}/api/v4/projects/$(echo "$repo" | sed -e "s/\//%2f/g")/releases/permalink/latest" "$temp_file" "${param[@]}"
    yq ".tag_name" "$temp_file"
  fi
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
function binary::download_and_extract {
  local name location url version
  dybatpho::expect_args name location url version -- "$@"
  local sha256_asset="${5:-}"
  local output_path temp_suffix
  output_path="$(dybatpho::path_join "$location" "$name")"
  temp_suffix="$(__binary_download_temp_suffix "$url")"
  dybatpho::create_temp temp_file "$temp_suffix"
  dybatpho::debug "Downloaded $url to $temp_file"
  dybatpho::dry_run dybatpho::curl_download "$url" "$temp_file"

  if ! dybatpho::string_is_blank "${sha256_asset}"; then
    binary::verify_sha256 "${name}" "${temp_file}" "${url}" "${sha256_asset}"
  fi

  dybatpho::create_temp before_path ".sh"
  dytoy::create_script "$name" "$before_path" "$(dytoy::get_yaml "$name" "hook.before")" "before-hook"
  dytoy::run_script "$before_path"

  if [[ "$url" =~ \.(tar\.gz|tgz|tar\.xz|tar\.bz2|tbz2|xz|tar|tar\.zst|tbz)$ ]]; then
    compressed:extract_tar "$name" "$temp_file" "$location" "$url" "$version"
  elif [[ "$url" =~ \.zip$ ]]; then
    compressed:extract_zip "$name" "$temp_file" "$location" "$version"
  elif [[ "$url" =~ \.bz2$ ]]; then
    compressed:extract_bzip2 "$name" "$temp_file" "$location"
  elif [[ "$url" =~ \.gz$ ]]; then
    compressed:extract_gzip "$name" "$temp_file" "$location"
  else
    dybatpho::dry_run mv "$temp_file" "$output_path"
  fi
  if ! dybatpho::is true "$LIST_CONTENTS"; then
    dybatpho::dry_run chmod +x "$output_path"
  fi

  dybatpho::create_temp after_path ".sh"
  dytoy::create_script "$name" "$after_path" "$(dytoy::get_yaml "$name" "hook.after")" "after-hook"
  dytoy::run_script "$after_path"

  dybatpho::success "Installed binary tool: $name"
}
