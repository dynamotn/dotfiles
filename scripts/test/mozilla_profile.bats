setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/mozilla_profile.sh"

  MOZILLA_APP_NAME="testbird"
  MOZILLA_APP_KIND="test client"
  MOZILLA_PROCESS="testbird-process"
  MOZILLA_PROFILE_ROOT="${BATS_TEST_TMPDIR}/profiles"
  MOZILLA_TEMPLATE_ROOT="${BATS_TEST_TMPDIR}/templates"
  MOZILLA_PROFILES=(public personal enterprise-F1)
  MOZILLA_FAILED_STORES=0
  PROFILE=""
  REFRESH="false"
  mkdir -p "${MOZILLA_PROFILE_ROOT}" "${MOZILLA_TEMPLATE_ROOT}"
}

# Puts an executable of that name first on PATH, exiting with the given code
# and echoing its arguments, so a test can watch what the library calls.
function fake_command {
  local name exit_code
  dybatpho::expect_args name exit_code -- "$@"
  cat > "${HOME}/.local/bin/${name}" << EOF
#!/usr/bin/env bash
printf '${name} %s\n' "\$*"
exit ${exit_code}
EOF
  chmod +x "${HOME}/.local/bin/${name}"
}

# Writes its standard input as the `prefs.js` of the personal profile and
# leaves its path in PREFS_FILE; `output` belongs to bats, so nothing here
# hands a path back through standard output.
function write_prefs {
  local profile_dir
  profile_dir="$(mozilla::profile_dir personal)"
  mkdir -p "${profile_dir}"
  PREFS_FILE="${profile_dir}/prefs.js"
  cat > "${PREFS_FILE}"
}

@test "mozilla::profile_dir and mozilla::prefs_template_dir follow the configured roots" {
  run mozilla::profile_dir personal
  assert_success
  assert_output "${MOZILLA_PROFILE_ROOT}/personal"

  run mozilla::prefs_template_dir personal
  assert_success
  assert_output "${MOZILLA_TEMPLATE_ROOT}/personal"
}

@test "mozilla::selected takes every profile until one is asked for" {
  run mozilla::selected personal
  assert_success

  PROFILE="personal"
  run mozilla::selected personal
  assert_success
  run mozilla::selected public
  assert_failure
}

@test "mozilla::validate_profile accepts a known profile and lists the others" {
  run mozilla::validate_profile ""
  assert_success
  run mozilla::validate_profile enterprise-F1
  assert_success

  run mozilla::validate_profile nosuch
  assert_failure
  assert_output --partial "'public' 'personal' 'enterprise-F1'"
}

@test "mozilla::for_each_profile runs the callback on the selected profiles only" {
  function record { printf 'seen %s\n' "$1"; }

  run mozilla::for_each_profile record
  assert_success
  assert_line "seen public"
  assert_line "seen personal"
  assert_line "seen enterprise-F1"

  PROFILE="personal"
  run mozilla::for_each_profile record
  assert_success
  assert_line "seen personal"
  refute_line "seen public"
}

@test "mozilla::extract_prefs writes the matching preferences in pattern order" {
  write_prefs << 'EOF'
user_pref("mail.account.lastKey", 3);
user_pref("privacy.userContext.extension", "x");
user_pref("mail.smtpservers", "smtp1");
EOF
  local template_file="${MOZILLA_TEMPLATE_ROOT}/03-email.js"

  run mozilla::extract_prefs "${template_file}" "${PREFS_FILE}" "mail.account" "mail.smtpservers"
  assert_success
  run cat "${template_file}"
  assert_line --index 0 --partial "mail.account.lastKey"
  assert_line --index 1 --partial "mail.smtpservers"
  refute_output --partial "privacy.userContext"
}

@test "mozilla::extract_prefs keeps the template when no preference matches" {
  write_prefs << 'EOF'
user_pref("mail.account.lastKey", 3);
EOF
  local template_file="${MOZILLA_TEMPLATE_ROOT}/03-email.js"
  printf 'previous content\n' > "${template_file}"

  run mozilla::extract_prefs "${template_file}" "${PREFS_FILE}" "calendar.registry"
  assert_success
  assert_output --partial "keeping ${template_file} as it is"
  assert_equal "$(cat "${template_file}")" "previous content"
}

@test "mozilla::add tracks every file of a folder with chezmoi" {
  export DRY_RUN=true
  local folder="${BATS_TEST_TMPDIR}/live"
  mkdir -p "${folder}"
  touch "${folder}/addons.json" "${folder}/extensions.json"

  run mozilla::add "${folder}" "addons.json" "extensions.json"
  assert_success
  assert_output --partial "chezmoi add ${folder}/addons.json --create"
  assert_output --partial "chezmoi add ${folder}/extensions.json --create"
}

@test "mozilla::store encrypts for a private profile and adds for the public one" {
  export DRY_RUN=true
  local folder="${BATS_TEST_TMPDIR}/live"
  mkdir -p "${folder}"
  touch "${folder}/cookies.sqlite" "${folder}/key4.db"

  run mozilla::store personal "${folder}" "cookies.sqlite" "key4.db"
  assert_success
  assert_output --partial "chezmoi-dycrypt encrypt -i personal -f ${folder} -a create cookies.sqlite key4.db"

  run mozilla::store public "${folder}" "cookies.sqlite"
  assert_success
  assert_output --partial "chezmoi add ${folder}/cookies.sqlite --create"
  refute_output --partial "chezmoi-dycrypt"
}

@test "mozilla::add walks past a file the profile does not have" {
  export DRY_RUN=true
  local folder="${BATS_TEST_TMPDIR}/live"
  mkdir -p "${folder}"
  touch "${folder}/addons.json"

  run mozilla::add "${folder}" "addons.json" "absent.json" "glob*.json"
  assert_success
  assert_output --partial "chezmoi add ${folder}/addons.json --create"
  refute_output --partial "chezmoi add ${folder}/absent.json"
  refute_output --partial "chezmoi add ${folder}/glob"
}

@test "mozilla::store counts a folder it could not encrypt" {
  fake_command chezmoi-dycrypt 1
  local folder="${BATS_TEST_TMPDIR}/live"
  mkdir -p "${folder}"

  run mozilla::store personal "${folder}" "cookies.sqlite" "key4.db"
  assert_success
  assert_output --partial "Cannot encrypt 2 file(s) of ${folder}"

  mozilla::store personal "${folder}" "cookies.sqlite" || true
  assert_equal "${MOZILLA_FAILED_STORES}" "1"
}

@test "mozilla::run reports the folders it could not encrypt" {
  fake_command pgrep 1
  function _update_profile { MOZILLA_FAILED_STORES=2; }

  run mozilla::run _update_profile
  assert_failure
  assert_output --partial "2 folder(s) could not be encrypted"
  refute_output --partial "DONE"
}

@test "mozilla::store_tree hands over one call per folder" {
  export DRY_RUN=true
  local root="${BATS_TEST_TMPDIR}/storage"
  mkdir -p "${root}/one" "${root}/two"
  touch "${root}/one/a.sqlite" "${root}/one/b.sqlite" "${root}/two/c.sqlite"

  run mozilla::store_tree personal "${root}"
  assert_success
  assert_output --partial "encrypt -i personal -f ${root}/one -a create a.sqlite b.sqlite"
  assert_output --partial "encrypt -i personal -f ${root}/two -a create c.sqlite"
}

@test "mozilla::store_tree narrows the files with the find predicates it is given" {
  export DRY_RUN=true
  local root="${BATS_TEST_TMPDIR}/storage"
  mkdir -p "${root}/moz-extension+++abc"
  touch "${root}/moz-extension+++abc/data.sqlite" "${root}/other.sqlite"

  run mozilla::store_tree personal "${root}" -path "*/moz-extension+++*"
  assert_success
  assert_output --partial "data.sqlite"
  refute_output --partial "other.sqlite"
}

@test "mozilla::store_tree walks past a folder that does not exist" {
  export DRY_RUN=true

  run mozilla::store_tree personal "${BATS_TEST_TMPDIR}/absent"
  assert_success
  refute_output --partial "chezmoi-dycrypt"
}

@test "mozilla::refresh_profile stops when the dotfiles cannot be laid down again" {
  fake_command chezmoi 1
  mkdir -p "$(mozilla::profile_dir personal)"

  run mozilla::refresh_profile personal
  assert_failure
  assert_output --partial "its live data is gone"
}

@test "mozilla::run refuses to touch the data while the application is running" {
  fake_command pgrep 0

  run mozilla::run _never_called
  assert_failure
  assert_output --partial "testbird is running"
}

@test "mozilla::run updates the dotfiles, or refreshes the live data" {
  fake_command pgrep 1
  function _update_profile { printf 'updated %s\n' "$1"; }

  run mozilla::run _update_profile
  assert_success
  assert_output --partial "updated personal"

  REFRESH="true"
  fake_command chezmoi 0
  run mozilla::run _update_profile
  assert_success
  assert_output --partial "chezmoi apply ${MOZILLA_PROFILE_ROOT}/personal --force"
  refute_output --partial "updated personal"
}
