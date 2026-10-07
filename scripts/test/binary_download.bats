setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/misc.sh"
  . "${DOTFILES_DIR}/scripts/lib/binary_download.sh"
}

@test "__binary_download_temp_suffix infers archive and binary suffixes" {
  run __binary_download_temp_suffix "https://example.com/tool.tar.gz"
  assert_success
  assert_output ".tar.gz"

  run __binary_download_temp_suffix "https://example.com/tool.zip"
  assert_success
  assert_output ".zip"

  run __binary_download_temp_suffix "https://example.com/tool.gz?download=1"
  assert_success
  assert_output ".gz"

  run __binary_download_temp_suffix "https://example.com/tool"
  assert_success
  assert_output ".bin"
}

@test "binary_download::get_latest_version queries the GitHub releases API" {
  local args_file="${BATS_TEST_TMPDIR}/curl-args"
  local headers_file="${BATS_TEST_TMPDIR}/curl-secret-headers"
  function dybatpho::curl_do {
    printf '%s\n' "$*" > "${args_file}"
    printf '%s\n' "${DYBATPHO_CURL_SECRET_HEADERS[@]}" > "${headers_file}"
    cat << 'EOF' > "$2"
{"tag_name": "v1.2.3"}
EOF
  }
  function grep {
    printf 'v1.2.3\n'
  }
  type="github"
  name="sample"
  export GITHUB_TOKEN="secret-token"

  run binary_download::get_latest_version github.com owner/repo
  assert_success
  assert_output --partial "v1.2.3"
  run cat "${args_file}"
  assert_success
  assert_output --partial "https://api.github.com/repos/owner/repo/releases/latest"
  refute_output --partial "secret-token"
  run cat "${headers_file}"
  assert_success
  assert_output "Authorization: Bearer secret-token"
}

@test "binary_download::get_latest_version queries the GitLab releases API" {
  local args_file="${BATS_TEST_TMPDIR}/curl-args"
  local headers_file="${BATS_TEST_TMPDIR}/curl-secret-headers"
  function dybatpho::curl_do {
    printf '%s\n' "$*" > "${args_file}"
    printf '%s\n' "${DYBATPHO_CURL_SECRET_HEADERS[@]}" > "${headers_file}"
    cat << 'EOF' > "$2"
tag_name: v9.8.7
EOF
  }
  type="gitlab"
  name="sample"
  export GITLAB_TOKEN="secret-token"

  run binary_download::get_latest_version gitlab.com owner/repo
  assert_success
  assert_output --partial 'v9.8.7'
  run cat "${args_file}"
  assert_success
  # The project path is percent-encoded with upper-case hex, as RFC 3986 asks
  # and as dybatpho::url_encode writes it; GitLab reads either case.
  assert_output --partial "https://gitlab.com/api/v4/projects/owner%2Frepo/releases/permalink/latest"
  refute_output --partial "secret-token"
  run cat "${headers_file}"
  assert_success
  assert_output "Authorization: Bearer secret-token"
}

@test "binary_download::get_latest_version sends no secret header without a token" {
  local headers_file="${BATS_TEST_TMPDIR}/curl-secret-headers"
  function dybatpho::curl_do {
    printf '%s\n' "${#DYBATPHO_CURL_SECRET_HEADERS[@]}" > "${headers_file}"
    printf '{"tag_name": "v1.2.3"}\n' > "$2"
  }
  type="github"
  name="sample"
  unset GITHUB_TOKEN

  run binary_download::get_latest_version github.com owner/repo
  assert_success
  run cat "${headers_file}"
  assert_success
  assert_output "0"
}

@test "binary_download::download_and_extract unpacks a tarball keeping its tree" {
  function dytoy::create_script { :; }
  function dytoy::run_script { :; }
  function dytoy::get_yaml { printf 'null
'; }
  function dybatpho::curl_download { :; }
  function __binary_download_extract_archive {
    printf '%s %s %s
' "$2" "$5" "$6" > "${BATS_TEST_TMPDIR}/archive-path"
    mkdir -p "$3"
    : > "$3/$1"
  }
  function __binary_download_extract_single_file { return 99; }

  run binary_download::download_and_extract sample "${BATS_TEST_TMPDIR}/out" "https://example.com/tool.tar.gz" "v1.0.0"
  assert_success
  run cat "${BATS_TEST_TMPDIR}/archive-path"
  assert_success
  assert_output --regexp '.*\.tar\.gz tree true$'
}

@test "binary_download::download_and_extract flattens a zip" {
  function dytoy::create_script { :; }
  function dytoy::run_script { :; }
  function dytoy::get_yaml { printf 'null\n'; }
  function dybatpho::curl_download { :; }
  function __binary_download_extract_archive {
    printf '%s %s %s\n' "$2" "$5" "$6" > "${BATS_TEST_TMPDIR}/archive-path"
    mkdir -p "$3"
    : > "$3/$1"
  }
  function __binary_download_extract_single_file { return 99; }

  run binary_download::download_and_extract sample "${BATS_TEST_TMPDIR}/out" "https://example.com/tool.zip?download=1" "v1.0.0"
  assert_success
  run cat "${BATS_TEST_TMPDIR}/archive-path"
  assert_success
  assert_output --regexp '.*\.zip flat false$'
}

@test "binary_download::download_and_extract decompresses a single gzip file" {
  function dytoy::create_script { :; }
  function dytoy::run_script { :; }
  function dytoy::get_yaml { printf 'null
'; }
  function dybatpho::curl_download { :; }
  function __binary_download_extract_archive { return 99; }
  function __binary_download_extract_single_file {
    printf '%s
' "$2" > "${BATS_TEST_TMPDIR}/archive-path"
    mkdir -p "$3"
    : > "$3/$1"
  }

  run binary_download::download_and_extract sample "${BATS_TEST_TMPDIR}/out" "https://example.com/tool.gz" "v1.0.0"
  assert_success
  run cat "${BATS_TEST_TMPDIR}/archive-path"
  assert_success
  assert_output --regexp '.*\.gz$'
}

@test "binary_download::download_and_extract falls back to moving plain binaries" {
  function dytoy::create_script { :; }
  function dytoy::run_script { :; }
  function dytoy::get_yaml { printf 'null
'; }
  function dybatpho::curl_download { printf 'binary-data' > "$2"; }
  mkdir -p "${BATS_TEST_TMPDIR}/out"

  run binary_download::download_and_extract sample "${BATS_TEST_TMPDIR}/out" "https://example.com/tool" "v1.0.0"
  assert_success
  assert_file_exist "${BATS_TEST_TMPDIR}/out/sample"
  run cat "${BATS_TEST_TMPDIR}/out/sample"
  assert_success
  assert_output "binary-data"
}

@test "binary_download::verify_sha256 passes when hash matches" {
  local asset_file="${BATS_TEST_TMPDIR}/tool.tar.gz"
  printf 'binary-data' > "${asset_file}"
  local actual_hash
  if command -v sha256sum > /dev/null 2>&1; then
    actual_hash=$(sha256sum "${asset_file}" | awk '{print $1}')
  else
    actual_hash=$(shasum -a 256 "${asset_file}" | awk '{print $1}')
  fi

  function dybatpho::curl_download {
    printf '%s  tool.tar.gz\n' "${actual_hash}" > "$2"
  }

  run binary_download::verify_sha256 \
    sample \
    "${asset_file}" \
    "https://example.com/v1.0.0/tool.tar.gz" \
    "checksums.txt"
  assert_success
}

@test "binary_download::verify_sha256 matches filenames prefixed with ./" {
  local asset_file="${BATS_TEST_TMPDIR}/tool"
  printf 'binary-data' > "${asset_file}"
  local actual_hash
  if command -v sha256sum > /dev/null 2>&1; then
    actual_hash=$(sha256sum "${asset_file}" | awk '{print $1}')
  else
    actual_hash=$(shasum -a 256 "${asset_file}" | awk '{print $1}')
  fi

  function dybatpho::curl_download {
    {
      printf '%s  ./tool\n' "${actual_hash}"
      printf '%s  ./tool-musl\n' "0000000000000000000000000000000000000000000000000000000000000000"
    } > "$2"
  }

  run binary_download::verify_sha256 \
    sample \
    "${asset_file}" \
    "https://example.com/v1.0.0/tool" \
    "SHASUMS256.asc"
  assert_success
}

@test "binary_download::verify_sha256 fails when hash does not match" {
  local asset_file="${BATS_TEST_TMPDIR}/tool.tar.gz"
  printf 'binary-data' > "${asset_file}"

  function dybatpho::curl_download {
    printf '%s  tool.tar.gz\n' "0000000000000000000000000000000000000000000000000000000000000000" > "$2"
  }

  run binary_download::verify_sha256 \
    sample \
    "${asset_file}" \
    "https://example.com/v1.0.0/tool.tar.gz" \
    "checksums.txt"
  assert_failure
  assert_output --partial "SHA256 mismatch"
}

@test "binary_download::verify_sha256 fails when asset name not found in checksum file" {
  local asset_file="${BATS_TEST_TMPDIR}/tool.tar.gz"
  printf 'binary-data' > "${asset_file}"

  function dybatpho::curl_download {
    printf '%s  other-tool.tar.gz\n' "abc123" > "$2"
  }

  run binary_download::verify_sha256 \
    sample \
    "${asset_file}" \
    "https://example.com/v1.0.0/tool.tar.gz" \
    "checksums.txt"
  assert_failure
  assert_output --partial "SHA256 hash not found"
}

@test "binary_download::download_and_extract skips sha256 when sha256_asset is empty" {
  function dytoy::create_script { :; }
  function dytoy::run_script { :; }
  function dytoy::get_yaml { printf 'null\n'; }
  function dybatpho::curl_download { printf 'binary-data' > "$2"; }
  function binary_download::verify_sha256 { return 99; }
  mkdir -p "${BATS_TEST_TMPDIR}/out"

  run binary_download::download_and_extract sample "${BATS_TEST_TMPDIR}/out" "https://example.com/tool" "v1.0.0" ""
  assert_success
}

@test "binary_download::download_and_extract calls verify_sha256 when sha256_asset is set" {
  local verify_called="${BATS_TEST_TMPDIR}/verify-called"
  function dytoy::create_script { :; }
  function dytoy::run_script { :; }
  function dytoy::get_yaml { printf 'null\n'; }
  function dybatpho::curl_download { printf 'binary-data' > "$2"; }
  function binary_download::verify_sha256 { touch "${verify_called}"; }
  mkdir -p "${BATS_TEST_TMPDIR}/out"

  run binary_download::download_and_extract sample "${BATS_TEST_TMPDIR}/out" "https://example.com/tool" "v1.0.0" "checksums.txt"
  assert_success
  assert_file_exist "${verify_called}"
}

@test "binary_download::verify_sha256 accepts an upper-case digest" {
  local asset_file="${BATS_TEST_TMPDIR}/tool.tar.gz"
  printf 'binary-data' > "${asset_file}"
  local actual_hash
  actual_hash="$(dybatpho::file_hash "${asset_file}" sha256)"

  function dybatpho::curl_download {
    printf '%s  tool.tar.gz\n' "${actual_hash^^}" > "$2"
  }

  run binary_download::verify_sha256 \
    sample \
    "${asset_file}" \
    "https://example.com/v1.0.0/tool.tar.gz" \
    "checksums.txt"
  assert_success
}

@test "binary_download::verify_sha256 reports a listed value that is no digest as a mismatch" {
  local asset_file="${BATS_TEST_TMPDIR}/tool.tar.gz"
  printf 'binary-data' > "${asset_file}"

  function dybatpho::curl_download {
    printf '%s  tool.tar.gz\n' "abc123" > "$2"
  }

  run binary_download::verify_sha256 \
    sample \
    "${asset_file}" \
    "https://example.com/v1.0.0/tool.tar.gz" \
    "checksums.txt"
  assert_failure
  assert_output --partial "SHA256 mismatch"
}

@test "__binary_download_run_hook renders the hook of a tool and runs it" {
  local calls="${BATS_TEST_TMPDIR}/hook-calls"
  function dytoy::get_yaml { printf 'echo %s\n' "$2"; }
  function dytoy::create_script {
    printf 'create %s %s %s %s\n' "$1" "$3" "$4" "$5" >> "${calls}"
    printf '%s\n' "$2" > "${BATS_TEST_TMPDIR}/script-path"
  }
  function dytoy::run_script { printf 'run %s\n' "$1" >> "${calls}"; }

  run __binary_download_run_hook sample hook.before before-hook v1.0.0
  assert_success
  local script_path
  script_path="$(< "${BATS_TEST_TMPDIR}/script-path")"
  run cat "${calls}"
  assert_success
  assert_line --index 0 "create sample echo hook.before before-hook v1.0.0"
  assert_line --index 1 "run ${script_path}"
}

@test "__binary_download_run_hook renders an empty hook when the specification cannot be read" {
  local calls="${BATS_TEST_TMPDIR}/hook-calls"
  function dytoy::get_yaml { return 1; }
  function dytoy::create_script { printf 'create [%s]\n' "$3" >> "${calls}"; }
  function dytoy::run_script { printf 'run\n' >> "${calls}"; }

  run __binary_download_run_hook sample hook.after after-hook v1.0.0
  assert_success
  run cat "${calls}"
  assert_success
  assert_line --index 0 "create []"
  assert_line --index 1 "run"
}

@test "__binary_download_strip_path removes leading path components" {
  run __binary_download_strip_path "bundle/bin/tool" 2
  assert_success
  assert_output "tool"

  run __binary_download_strip_path "bundle/bin/tool" 0
  assert_success
  assert_output "bundle/bin/tool"
}

@test "__binary_download_extract_archive keeps a tarball's tree and renames its first entry" {
  local src_dir="${BATS_TEST_TMPDIR}/src"
  local archive_path="${BATS_TEST_TMPDIR}/bundle.tar.gz"
  local destination="${BATS_TEST_TMPDIR}/custom-bin"
  mkdir -p "${src_dir}/bundle/bin"
  printf 'hello tar
' > "${src_dir}/bundle/bin/tool"
  tar -czf "${archive_path}" -C "${src_dir}" bundle

  function dytoy::get_yaml {
    if [[ "$2" == "archive" ]]; then
      printf '{"path":"bundle/bin/tool","location":"%s","strip":2}
' "${destination}"
    else
      printf 'null
'
    fi
  }

  run __binary_download_extract_archive mytool "${archive_path}" "${BATS_TEST_TMPDIR}/ignored" "v1.0.0" tree true
  assert_success
  assert_file_exist "${destination}/mytool"
  run cat "${destination}/mytool"
  assert_success
  assert_output "hello tar"
}

@test "__binary_download_extract_archive flattens the entries of a zip" {
  local src_dir="${BATS_TEST_TMPDIR}/src"
  local archive_path="${BATS_TEST_TMPDIR}/bundle.zip"
  local destination="${BATS_TEST_TMPDIR}/custom-bin"
  mkdir -p "${src_dir}/bundle/bin"
  printf 'hello zip
' > "${src_dir}/bundle/bin/tool"
  python3 - << PY
from pathlib import Path
import zipfile
src = Path("${src_dir}")
archive = Path("${archive_path}")
with zipfile.ZipFile(archive, "w") as zf:
    zf.write(src / "bundle" / "bin" / "tool", arcname="bundle/bin/tool")
PY

  function dytoy::get_yaml {
    if [[ "$2" == "archive" ]]; then
      printf '{"path":"bundle/bin/tool","location":"%s","strip":1}
' "${destination}"
    else
      printf 'null
'
    fi
  }

  run __binary_download_extract_archive mytool "${archive_path}" "${BATS_TEST_TMPDIR}/ignored" "v1.0.0" flat false
  assert_success
  assert_file_exist "${destination}/tool"
  run cat "${destination}/tool"
  assert_success
  assert_output "hello zip"
}

@test "__binary_download_extract_single_file renames extracted output to the target command name" {
  function dybatpho::archive_extract {
    mkdir -p "$2"
    printf 'hello single
' > "$2/downloaded"
  }

  run __binary_download_extract_single_file mytool "${BATS_TEST_TMPDIR}/downloaded.gz" "${BATS_TEST_TMPDIR}/out"
  assert_success
  assert_file_exist "${BATS_TEST_TMPDIR}/out/mytool"
  run cat "${BATS_TEST_TMPDIR}/out/mytool"
  assert_success
  assert_output "hello single"
}

@test "a dry run shows the copy as a command that could be pasted back" {
  # The whole command used to reach `dybatpho::dry_run` as one string, so it
  # came out as a single quoted word rather than `cp` and its arguments.
  export DRY_RUN="true"
  local root="${BATS_TEST_TMPDIR}/extracted root" destination="${BATS_TEST_TMPDIR}/the dest"
  run __binary_download_copy_selection "${root}" "bin/*" "${destination}" 0 tree ""
  assert_success
  assert_output "🧪 DRY RUN: $(printf '%q ' cp -R "${root}/bin/*" "${destination}" | sed 's/ $//')"
}
