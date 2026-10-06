setup() {
  load test_helper
  setup_dotfiles_test_env

  HOOK="${BATS_TEST_TMPDIR}/pre-commit"
  render_template \
    "home/private_dot_config/git/templates/hooks/executable_pre-commit.tmpl" "${HOOK}"

  REPO="${BATS_TEST_TMPDIR}/repo"
  dybatpho::ensure_dir "${REPO}" > /dev/null
  git -C "${REPO}" init -q
  git -C "${REPO}" config user.name "Test"
  git -C "${REPO}" config user.email "test@example.com"
  printf 'seed\n' > "${REPO}/seed.txt"
  git -C "${REPO}" add seed.txt
  git -C "${REPO}" commit -q -m "seed"

  # The markers are assembled at run time so that no line of this file starts
  # with one, which would make the repository's own hook reject its test.
  OPEN="$(printf '<%.0s' {1..7})"
  BASE="$(printf '|%.0s' {1..7})"
  SPLIT="$(printf '=%.0s' {1..7})"
  CLOSE="$(printf '>%.0s' {1..7})"

  cd "${REPO}" || return 1
}

function stage {
  local path
  dybatpho::expect_args path -- "$@"
  cat > "${REPO}/${path}"
  git -C "${REPO}" add -- "${path}"
}

@test "pre-commit rejects staged content holding conflict markers" {
  stage "merged.txt" << EOF
ours
${OPEN} HEAD
mine
${SPLIT}
theirs
${CLOSE} other
EOF

  run bash "${HOOK}"
  assert_failure
  assert_output --partial "merged.txt:2"
  assert_output --partial "merged.txt:6"
  assert_output --partial "Resolve the conflict markers before committing"
}

@test "pre-commit rejects the diff3 base marker" {
  stage "merged.txt" << EOF
${OPEN} ours
mine
${BASE} base
common
${SPLIT}
theirs
${CLOSE} theirs
EOF

  run bash "${HOOK}"
  assert_failure
  assert_output --partial "merged.txt:3"
}

@test "pre-commit accepts the commit that resolves a conflict" {
  stage "merged.txt" << EOF
ours
${OPEN} HEAD
mine
${SPLIT}
theirs
${CLOSE} other
EOF
  git -C "${REPO}" commit -q -m "conflicted"

  stage "merged.txt" << EOF
ours
mine
EOF

  run bash "${HOOK}"
  assert_success
}

@test "pre-commit accepts a Setext heading and other divider lines" {
  stage "README.md" << EOF
Title
${SPLIT}

body
EOF

  run bash "${HOOK}"
  assert_success
}

@test "pre-commit skips a file that opts out with a gitattribute" {
  printf 'fixture.txt conflict-markers=allowed\n' > "${REPO}/.gitattributes"
  git -C "${REPO}" add .gitattributes
  stage "fixture.txt" << EOF
${OPEN} HEAD
${SPLIT}
${CLOSE} other
EOF

  run bash "${HOOK}"
  assert_success
}

@test "pre-commit skips binary content and deleted files" {
  printf '\x00\x01%s HEAD\x00' "${OPEN}" > "${REPO}/blob.bin"
  git -C "${REPO}" add blob.bin
  git -C "${REPO}" rm -q seed.txt

  run bash "${HOOK}"
  assert_success
}

@test "pre-commit accepts a path whose name holds glob characters" {
  stage 'we[i]rd*.txt' << EOF
clean
EOF

  run bash "${HOOK}"
  assert_success
}

@test "pre-commit accepts an empty index" {
  run bash "${HOOK}"
  assert_success
}
