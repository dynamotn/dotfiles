# dyshellint disable=SC2154 DOTFILES_DIR and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/pins.sh"
}

@test "pins::list finds every pin of the repository, each with a digest" {
  run pins::list "${DOTFILES_DIR}"
  assert_success
  # Ten in setup.sh, three in age.yaml.tmpl, the delta theme.
  assert_equal "${#lines[@]}" 14
  local file key url digest
  while IFS=$'\t' read -r file key url digest; do
    [[ "${url}" == https://* ]] || fail "${file} ${key}: no URL"
    [[ "${digest}" =~ ^[0-9a-f]{64}$ ]] || fail "${file} ${key}: no digest"
  done <<< "${output}"
}

@test "age.yaml.tmpl pins the same release and linux archives as setup.sh" {
  local listed
  listed="$(pins::list "${DOTFILES_DIR}")"
  local file key url digest
  while IFS=$'\t' read -r file key url digest; do
    [[ "${file}" == */age.yaml.tmpl ]] || continue
    grep -qF "$(printf 'scripts/setup.sh\tAGE_SHA256[linux_%s]\t%s\t%s' "${key}" "${url}" "${digest}")" \
      <<< "${listed}" || fail "age.yaml.tmpl ${key} differs from setup.sh: ${url} ${digest}"
  done <<< "${listed}"
}

@test "pins::check fails on a digest that is not the asset's, and names the right one" {
  local root="${BATS_TEST_TMPDIR}/repo" good
  mkdir -p "${root}/scripts" "${root}/home/.chezmoitemplates/dytoy" "${root}/home/.chezmoiexternals"
  # Every download is the same payload.
  function dybatpho::curl_download { printf 'payload\n' > "$2"; }
  printf 'payload\n' > "${BATS_TEST_TMPDIR}/payload"
  good="$(dybatpho::file_hash "${BATS_TEST_TMPDIR}/payload" sha256)"
  printf 'AGE_VERSION="v1.0.0"\ndeclare -A AGE_SHA256=(\n  [linux_amd64]="%s"\n)\n' "${good}" \
    > "${root}/scripts/setup.sh"
  printf '      "amd64" "%s" }}\n  version: v1.0.0\n' "${good}" \
    > "${root}/home/.chezmoitemplates/dytoy/age.yaml.tmpl"
  printf '  url: https://raw.githubusercontent.com/catppuccin/delta/%s/x\n  checksum:\n    sha256: "%s"\n' \
    "$(printf 'a%.0s' {1..40})" "${good}" > "${root}/home/.chezmoiexternals/catppuccin.yaml.tmpl"
  run pins::check "${root}"
  assert_success
  assert_output ""
  # A version bumped without its digest, as Renovate leaves it.
  sed -i.bak "s/${good}/$(printf '0%.0s' {1..64})/" "${root}/scripts/setup.sh"
  run pins::check "${root}"
  assert_failure
  assert_output --partial "scripts/setup.sh AGE_SHA256[linux_amd64]: pinned 0000"
  assert_output --partial "is ${good}"
}
