#!/usr/bin/env bash
# shellcheck disable=2154,2155

#######################################
# @description Get latest version of tool from GitHub or GitLab
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
    dybatpho::curl_do "https://api.${host}/repos/${repo}/releases/latest" "$temp_file" -H "'Authorization: Bearer ${GITHUB_TOKEN:-}'"
    grep -Po "tag_name\": \"(\K.*)(?=\",)" "$temp_file"
  elif [ "$type" = "gitlab" ]; then
    dybatpho::curl_do "https://${host}/api/v4/projects/$(echo "$repo" | sed -e "s/\//%2f/g")/releases/permalink/latest" "$temp_file" -H "Authorization: Bearer ${GITLAB_TOKEN:-}"
    yq ".tag_name" "$temp_file"
  fi
}

#######################################
# @description Download tool from release file and extract it
# @arg $1 string File name of command
# @arg $2 string Location to download/extract file
# @arg $3 string URL of file
# @env LIST_CONTENTS boolean If false, grant execute permission extracted file
#######################################
function binary::download_and_extract {
  local name location url
  dybatpho::expect_args name location url -- "$@"
  dybatpho::create_temp temp_file ".z"
  dybatpho::debug "Downloaded $url to $temp_file"
  dybatpho::dry_run dybatpho::curl_download "$url" "$temp_file"

  dybatpho::create_temp before_path ".sh"
  dytoy::create_script "$name" "$before_path" "$(dytoy::get_yaml "$name" "hook.before")" "before-hook"
  dytoy::run_script "$before_path"

  if [[ "$url" =~ \.(tar\.gz|tgz|tar\.xz|tar\.bz2|tbz2|xz|tar|tar\.zst|tbz)$ ]]; then
    compressed:extract_tar "$name" "$temp_file" "$location" "$url"
  elif [[ "$url" =~ \.zip$ ]]; then
    compressed:extract_zip "$name" "$temp_file" "$location"
  elif [[ "$url" =~ \.bz2$ ]]; then
    compressed:extract_bzip2 "$name" "$temp_file" "$location"
  elif [[ "$url" =~ \.gz$ ]]; then
    compressed:extract_gzip "$name" "$temp_file" "$location"
  else
    dybatpho::dry_run mv "$temp_file" "${location}/${name}"
  fi
  if ! dybatpho::is true "$LIST_CONTENTS"; then
    dybatpho::dry_run chmod +x "${location}/${name}"
  fi

  dybatpho::create_temp after_path ".sh"
  dytoy::create_script "$name" "$after_path" "$(dytoy::get_yaml "$name" "hook.after")" "after-hook"
  dytoy::run_script "$after_path"

  dybatpho::success "Installed binary tool: $name"
}
