#!/usr/bin/env bash
# @file pins.sh
# @brief Library `pins` for the sha256 digests pinned beside a version
# @description Renovate bumps the versions and commits these files pin, but
# cannot recompute the sha256 of an asset pinned beside them: a bump alone
# would stop setup.sh, or every `chezmoi apply`, on a checksum mismatch.
# `pins::check` downloads each pinned asset and compares, so such a pull
# request fails CI instead and prints the digests to write.

#######################################
# @description Print every pinned asset of the repository
# @arg $1 string Root of the repository
# @stdout One `file<TAB>key<TAB>url<TAB>digest` line per asset, the file
# relative to the root
#######################################
function pins::list {
  local root
  dybatpho::expect_args root -- "$@"
  local setup="scripts/setup.sh" age="home/.chezmoitemplates/dytoy/age.yaml.tmpl"
  local version table key digest url tables digests
  # setup.sh: AGE_VERSION, YQ_VERSION, and a table of `[os_arch]="digest"`
  # lines for each.
  tables="$(awk '
    /^declare -A [A-Z]+_SHA256=\(/ { table = $3; sub(/_SHA256=\(.*/, "", table); next }
    table && /^\)/ { table = ""; next }
    table && match($0, /\[[a-z0-9_]+\]="[0-9a-f]+"/) {
      line = substr($0, RSTART, RLENGTH); gsub(/[\[\]"]/, "", line); split(line, kv, "=")
      printf "%s\t%s\t%s\n", table, kv[1], kv[2]
    }' "${root}/${setup}")"
  while IFS=$'\t' read -r table key digest; do
    [[ -n "${table}" ]] || continue
    version="$(sed -n "s/^${table}_VERSION=\"\\(.*\\)\"$/\\1/p" "${root}/${setup}")"
    case "${table}" in
      AGE)
        url="https://github.com/FiloSottile/age/releases/download/${version}"
        url+="/age-${version}-${key%%_*}-${key#*_}.tar.gz"
        ;;
      YQ) url="https://github.com/mikefarah/yq/releases/download/${version}/yq_${key}" ;;
      *) dybatpho::die "Unknown table ${table} in ${setup}" ;;
    esac
    printf '%s\t%s\t%s\t%s\n' "${setup}" "${table}_SHA256[${key}]" "${url}" "${digest}"
  done <<< "${tables}"
  # age.yaml.tmpl: the release of the linux archives, one digest per arch.
  version="$(sed -n 's/^  version: \(v[0-9.]*\)$/\1/p' "${root}/${age}")"
  digests="$(sed -n 's/^ *"\([a-z0-9]*\)" "\([0-9a-f]\{64\}\)".*$/\1 \2/p' "${root}/${age}")"
  while read -r key digest; do
    [[ -n "${key}" ]] || continue
    url="https://github.com/FiloSottile/age/releases/download/${version}/age-${version}-linux-${key}.tar.gz"
    printf '%s\t%s\t%s\t%s\n' "${age}" "${key}" "${url}" "${digest}"
  done <<< "${digests}"
  # The externals fetched at a commit with their checksum, the delta theme
  # among them: each target, then its url, then its sha256.
  local external
  for external in "${root}"/home/.chezmoiexternals/*.tmpl; do
    [[ -e "${external}" ]] || continue
    awk -v file="${external#"${root}/"}" '
      /^[^ ].*:$/ && !/^\{\{-/ { key = $0; sub(/:$/, "", key); url = ""; next }
      /^  url: .*raw\.githubusercontent\.com\/[^\/]+\/[^\/]+\/[0-9a-f]{40}\// {
        url = $0; sub(/^  url: /, "", url); gsub(/[\047"]/, "", url); next
      }
      url && /^ +sha256: / {
        digest = $0; sub(/^ +sha256: /, "", digest); gsub(/"/, "", digest)
        # Never an empty field: read takes a run of tabs for one.
        printf "%s\t%s\t%s\t%s\n", file, (key == "" ? "-" : key), url, digest; url = ""
      }' "${external}"
  done
  # The tridactyl installer, at a release tag, with its checksum.
  local tridactyl="home/.chezmoiscripts/run_once_after_03-setup-tridactyl.sh.tmpl"
  version="$(sed -n 's/^installer_version="\(.*\)"$/\1/p' "${root}/${tridactyl}")"
  digest="$(sed -n 's/^installer_sha256="\(.*\)"$/\1/p' "${root}/${tridactyl}")"
  url="https://raw.githubusercontent.com/tridactyl/native_messenger/${version}/installers/install.sh"
  printf '%s\t%s\t%s\t%s\n' "${tridactyl}" "installer" "${url}" "${digest}"
}

#######################################
# @description Download every pinned asset and compare it with its digest
# @arg $1 string Root of the repository
# @stdout One line per asset whose digest is wrong, with the right one
# @exitcode 0 Every digest matches
# @exitcode 1 One does not, or an asset could not be downloaded
#######################################
function pins::check {
  local root
  dybatpho::expect_args root -- "$@"
  local file key url digest actual download failed=0 checked=0 pins
  pins="$(pins::list "${root}")" || return 1
  while IFS=$'\t' read -r file key url digest; do
    checked=$((checked + 1))
    dybatpho::create_temp download ".pin"
    if ! dybatpho::curl_download "${url}" "${download}"; then
      printf '%s %s: cannot download %s\n' "${file}" "${key}" "${url}"
      failed=1
      continue
    fi
    actual="$(dybatpho::file_hash "${download}" sha256)"
    if [[ "${actual}" != "${digest}" ]]; then
      printf '%s %s: pinned %s, but %s is %s\n' "${file}" "${key}" "${digest:-nothing}" "${url}" "${actual}"
      failed=1
    fi
  done <<< "${pins}"
  ((checked > 0)) || dybatpho::die "No pinned asset found under ${root}"
  return "${failed}"
}
