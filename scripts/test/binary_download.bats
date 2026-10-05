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

@test "binary_download::download_and_extract routes tarballs through compressed::extract_tar" {
  function dytoy::create_script { :; }
  function dytoy::run_script { :; }
  function dytoy::get_yaml { printf 'null
'; }
  function dybatpho::curl_download { :; }
  function compressed::extract_tar {
    printf '%s
' "$2" > "${BATS_TEST_TMPDIR}/archive-path"
    mkdir -p "$3"
    : > "$3/$1"
  }
  function compressed::extract_zip { return 99; }
  function compressed::extract_bzip2 { return 99; }
  function compressed::extract_gzip { return 99; }

  run binary_download::download_and_extract sample "${BATS_TEST_TMPDIR}/out" "https://example.com/tool.tar.gz" "v1.0.0"
  assert_success
  run cat "${BATS_TEST_TMPDIR}/archive-path"
  assert_success
  assert_output --regexp '.*\.tar\.gz$'
}

@test "binary_download::download_and_extract routes gzip files through compressed::extract_gzip" {
  function dytoy::create_script { :; }
  function dytoy::run_script { :; }
  function dytoy::get_yaml { printf 'null
'; }
  function dybatpho::curl_download { :; }
  function compressed::extract_tar { return 99; }
  function compressed::extract_zip { return 99; }
  function compressed::extract_bzip2 { return 99; }
  function compressed::extract_gzip {
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
