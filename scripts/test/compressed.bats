setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/misc.sh"
  . "${DOTFILES_DIR}/scripts/lib/compressed.sh"
}

@test "__compressed_strip_path removes leading path components" {
  run __compressed_strip_path "bundle/bin/tool" 2
  assert_success
  assert_output "tool"

  run __compressed_strip_path "bundle/bin/tool" 0
  assert_success
  assert_output "bundle/bin/tool"
}

@test "compressed:extract_tar selects and renames the first matching entry" {
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

  run compressed:extract_tar mytool "${archive_path}" "${BATS_TEST_TMPDIR}/ignored" "https://example.com/tool.tar.gz" "v1.0.0"
  assert_success
  assert_file_exist "${destination}/mytool"
  run cat "${destination}/mytool"
  assert_success
  assert_output "hello tar"
}

@test "compressed:extract_zip flattens selected entries into the destination" {
  local src_dir="${BATS_TEST_TMPDIR}/src"
  local archive_path="${BATS_TEST_TMPDIR}/bundle.zip"
  local destination="${BATS_TEST_TMPDIR}/custom-bin"
  mkdir -p "${src_dir}/bundle/bin"
  printf 'hello zip
' > "${src_dir}/bundle/bin/tool"
  python3 - <<PY
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

  run compressed:extract_zip mytool "${archive_path}" "${BATS_TEST_TMPDIR}/ignored" "v1.0.0"
  assert_success
  assert_file_exist "${destination}/tool"
  run cat "${destination}/tool"
  assert_success
  assert_output "hello zip"
}

@test "__compressed_extract_single_file renames extracted output to the target command name" {
  function dybatpho::archive_extract {
    mkdir -p "$2"
    printf 'hello single
' > "$2/downloaded"
  }

  run __compressed_extract_single_file mytool "${BATS_TEST_TMPDIR}/downloaded.gz" "${BATS_TEST_TMPDIR}/out" ".gz"
  assert_success
  assert_file_exist "${BATS_TEST_TMPDIR}/out/mytool"
  run cat "${BATS_TEST_TMPDIR}/out/mytool"
  assert_success
  assert_output "hello single"
}

@test "compressed:extract_bzip2 delegates to __compressed_extract_single_file with .bz2 suffix" {
  function __compressed_extract_single_file {
    printf 'name:%s suffix:%s\n' "$1" "$4"
  }

  run compressed:extract_bzip2 mytool "${BATS_TEST_TMPDIR}/file.bz2" "${BATS_TEST_TMPDIR}/out"
  assert_success
  assert_output "name:mytool suffix:.bz2"
}

@test "compressed:extract_gzip delegates to __compressed_extract_single_file with .gz suffix" {
  function __compressed_extract_single_file {
    printf 'name:%s suffix:%s\n' "$1" "$4"
  }

  run compressed:extract_gzip mytool "${BATS_TEST_TMPDIR}/file.gz" "${BATS_TEST_TMPDIR}/out"
  assert_success
  assert_output "name:mytool suffix:.gz"
}
