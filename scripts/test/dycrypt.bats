setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/chezmoi_attrs.sh"
  . "${DOTFILES_DIR}/scripts/lib/dycrypt.sh"

  export DYCRYPT_DOTFILES_DIR="${BATS_TEST_TMPDIR}/dotfiles"
  dybatpho::ensure_dir "${DYCRYPT_DOTFILES_DIR}/secrets/data/test" > /dev/null
  age-keygen -o "$(dybatpho::xdg_config_dir chezmoi)/test.key" 2> /dev/null
  chmod 600 "$(dybatpho::xdg_config_dir chezmoi)/test.key"
}

function data_file {
  printf '%s' "${DYCRYPT_DOTFILES_DIR}/secrets/data/test/$1"
}

function write_data_file {
  local name content
  dybatpho::expect_args name content -- "$@"
  printf '%s\n' "${content}" > "$(data_file "${name}")"
}

function run_resolve {
  local identity filename folder attributes
  dybatpho::expect_args identity filename folder attributes -- "$@"
  local plain cipher
  dycrypt::resolve_paths plain cipher "${identity}" "${filename}" "${folder}" "${attributes}"
  printf '%s\n%s' "${plain}" "${cipher}"
}

@test "dycrypt::resolve_paths keeps the data store plaintext next to its ciphertext" {
  run run_resolve test "common.yaml" data ""
  assert_success
  assert_line --index 0 "${DYCRYPT_DOTFILES_DIR}/secrets/data/test/common.yaml"
  assert_line --index 1 "${DYCRYPT_DOTFILES_DIR}/secrets/data/test/common.yaml.age"
}

@test "dycrypt::resolve_paths sends a target file to its chezmoi source path" {
  run run_resolve test "places.sqlite" "${HOME}/.zen/profile" "create"
  assert_success
  assert_line --index 0 "${HOME}/.zen/profile/places.sqlite"
  assert_line --index 1 \
    "${DYCRYPT_DOTFILES_DIR}/home/private_dot_zen/profile/create_encrypted_places.sqlite.age"
}

@test "dycrypt::resolve_paths trims the file name and rejects an empty one" {
  run run_resolve test "  common.yaml  " data ""
  assert_success
  assert_line --index 0 "${DYCRYPT_DOTFILES_DIR}/secrets/data/test/common.yaml"

  run run_resolve test "   " data ""
  assert_failure
  assert_output --partial "must not be empty"
}

@test "dycrypt::validate_identity rejects an identity that could escape its folder" {
  run dycrypt::validate_identity "../../etc"
  assert_failure
  run dycrypt::validate_identity "enterprise-F1"
  assert_success
}

@test "dycrypt::encrypt and dycrypt::decrypt round trip a secret" {
  write_data_file secret.yaml "token: hunter2"

  run dycrypt::encrypt test "$(data_file secret.yaml)" "$(data_file secret.yaml.age)" false false
  assert_success
  assert [ -f "$(data_file secret.yaml.age)" ]

  rm -f "$(data_file secret.yaml)"
  run dycrypt::decrypt test "$(data_file secret.yaml.age)" "$(data_file secret.yaml)" false
  assert_success
  assert_equal "$(cat "$(data_file secret.yaml)")" "token: hunter2"
}

@test "dycrypt::decrypt writes the plaintext readable by its owner only" {
  write_data_file secret.yaml "token: hunter2"
  dycrypt::encrypt test "$(data_file secret.yaml)" "$(data_file secret.yaml.age)" false false
  rm -f "$(data_file secret.yaml)"

  dycrypt::decrypt test "$(data_file secret.yaml.age)" "$(data_file secret.yaml)" false
  assert_equal "$(stat -c '%a' "$(data_file secret.yaml)")" "600"
}

@test "dycrypt::encrypt leaves an up to date ciphertext alone" {
  write_data_file secret.yaml "token: hunter2"
  dycrypt::encrypt test "$(data_file secret.yaml)" "$(data_file secret.yaml.age)" false false
  local before
  before="$(cat "$(data_file secret.yaml.age)")"

  run dycrypt::encrypt test "$(data_file secret.yaml)" "$(data_file secret.yaml.age)" false false
  assert_success
  assert_equal "$(cat "$(data_file secret.yaml.age)")" "${before}"
}

@test "dycrypt::encrypt rewrites a ciphertext whose plaintext changed" {
  write_data_file secret.yaml "token: hunter2"
  dycrypt::encrypt test "$(data_file secret.yaml)" "$(data_file secret.yaml.age)" false false
  local before
  before="$(cat "$(data_file secret.yaml.age)")"

  write_data_file secret.yaml "token: changed"
  run dycrypt::encrypt test "$(data_file secret.yaml)" "$(data_file secret.yaml.age)" false false
  assert_success
  refute [ "$(cat "$(data_file secret.yaml.age)")" = "${before}" ]
}

@test "dycrypt::encrypt re-encrypts an up to date ciphertext when forced" {
  write_data_file secret.yaml "token: hunter2"
  dycrypt::encrypt test "$(data_file secret.yaml)" "$(data_file secret.yaml.age)" false false
  local before
  before="$(cat "$(data_file secret.yaml.age)")"

  run dycrypt::encrypt test "$(data_file secret.yaml)" "$(data_file secret.yaml.age)" true false
  assert_success
  refute [ "$(cat "$(data_file secret.yaml.age)")" = "${before}" ]
}

@test "dycrypt::encrypt removes the plaintext when asked" {
  write_data_file secret.yaml "token: hunter2"

  run dycrypt::encrypt test "$(data_file secret.yaml)" "$(data_file secret.yaml.age)" false true
  assert_success
  assert [ -f "$(data_file secret.yaml.age)" ]
  refute [ -f "$(data_file secret.yaml)" ]
}

@test "dycrypt::encrypt in a dry run touches nothing" {
  export DRY_RUN=true
  write_data_file secret.yaml "token: hunter2"
  local output="${DYCRYPT_DOTFILES_DIR}/home/nested/secret.yaml.age"

  run dycrypt::encrypt test "$(data_file secret.yaml)" "${output}" false true
  assert_success
  assert_output --partial "DRY RUN"
  refute [ -e "${output}" ]
  refute [ -d "${DYCRYPT_DOTFILES_DIR}/home/nested" ]
  assert [ -f "$(data_file secret.yaml)" ]
}

@test "dycrypt::encrypt reports a missing identity key instead of the age error" {
  write_data_file secret.yaml "token: hunter2"

  run dycrypt::encrypt nosuch "$(data_file secret.yaml)" "$(data_file secret.yaml.age)" false false
  assert_failure
  assert_output --partial "No age identity for 'nosuch'"
}

@test "dycrypt::encrypt reports a missing input file" {
  run dycrypt::encrypt test "$(data_file absent.yaml)" "$(data_file absent.yaml.age)" false false
  assert_failure
  assert_output --partial "is not a file"
}

@test "dycrypt::is_up_to_date treats an undecryptable ciphertext as outdated" {
  write_data_file secret.yaml "token: hunter2"
  printf 'not an age file\n' > "$(data_file secret.yaml.age)"

  run dycrypt::is_up_to_date "$(data_file secret.yaml)" "$(data_file secret.yaml.age)" \
    "$(dybatpho::xdg_config_dir chezmoi)/test.key"
  assert_failure
}
