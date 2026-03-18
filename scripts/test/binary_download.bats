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

@test "binary::get_latest_version queries the GitHub releases API" {
  local args_file="${BATS_TEST_TMPDIR}/curl-args"
  function dybatpho::curl_do {
    printf '%s\n' "$*" > "${args_file}"
    cat <<'EOF' > "$2"
{"tag_name": "v1.2.3"}
EOF
  }
  function grep {
    printf 'v1.2.3\n'
  }
  type="github"
  name="sample"
  export GITHUB_TOKEN="secret-token"

  run binary::get_latest_version github.com owner/repo
  assert_success
  assert_output --partial "v1.2.3"
  run cat "${args_file}"
  assert_success
  assert_output --partial "https://api.github.com/repos/owner/repo/releases/latest"
  assert_output --partial "Authorization: Bearer secret-token"
}

@test "binary::get_latest_version queries the GitLab releases API" {
  local args_file="${BATS_TEST_TMPDIR}/curl-args"
  function dybatpho::curl_do {
    printf '%s\n' "$*" > "${args_file}"
    cat <<'EOF' > "$2"
tag_name: v9.8.7
EOF
  }
  type="gitlab"
  name="sample"
  export GITLAB_TOKEN="secret-token"

  run binary::get_latest_version gitlab.com owner/repo
  assert_success
  assert_output --partial 'v9.8.7'
  run cat "${args_file}"
  assert_success
  assert_output --partial "https://gitlab.com/api/v4/projects/owner%2frepo/releases/permalink/latest"
  assert_output --partial "Authorization: Bearer secret-token"
}

@test "binary::download_and_extract routes tarballs through compressed:extract_tar" {
  function dytoy::create_script { :; }
  function dytoy::run_script { :; }
  function dytoy::get_yaml { printf 'null
'; }
  function dybatpho::curl_download { :; }
  function compressed:extract_tar {
    printf '%s
' "$2" > "${BATS_TEST_TMPDIR}/archive-path"
    mkdir -p "$3"
    : > "$3/$1"
  }
  function compressed:extract_zip { return 99; }
  function compressed:extract_bzip2 { return 99; }
  function compressed:extract_gzip { return 99; }

  run binary::download_and_extract sample "${BATS_TEST_TMPDIR}/out" "https://example.com/tool.tar.gz" "v1.0.0"
  assert_success
  run cat "${BATS_TEST_TMPDIR}/archive-path"
  assert_success
  assert_output --regexp '.*\.tar\.gz$'
}

@test "binary::download_and_extract routes gzip files through compressed:extract_gzip" {
  function dytoy::create_script { :; }
  function dytoy::run_script { :; }
  function dytoy::get_yaml { printf 'null
'; }
  function dybatpho::curl_download { :; }
  function compressed:extract_tar { return 99; }
  function compressed:extract_zip { return 99; }
  function compressed:extract_bzip2 { return 99; }
  function compressed:extract_gzip {
    printf '%s
' "$2" > "${BATS_TEST_TMPDIR}/archive-path"
    mkdir -p "$3"
    : > "$3/$1"
  }

  run binary::download_and_extract sample "${BATS_TEST_TMPDIR}/out" "https://example.com/tool.gz" "v1.0.0"
  assert_success
  run cat "${BATS_TEST_TMPDIR}/archive-path"
  assert_success
  assert_output --regexp '.*\.gz$'
}

@test "binary::download_and_extract falls back to moving plain binaries" {
  function dytoy::create_script { :; }
  function dytoy::run_script { :; }
  function dytoy::get_yaml { printf 'null
'; }
  function dybatpho::curl_download { printf 'binary-data' > "$2"; }
  mkdir -p "${BATS_TEST_TMPDIR}/out"

  run binary::download_and_extract sample "${BATS_TEST_TMPDIR}/out" "https://example.com/tool" "v1.0.0"
  assert_success
  assert_file_exist "${BATS_TEST_TMPDIR}/out/sample"
  run cat "${BATS_TEST_TMPDIR}/out/sample"
  assert_success
  assert_output "binary-data"
}
