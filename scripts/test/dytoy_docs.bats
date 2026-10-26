# dyshellint disable=SC2154 DOTFILES_DIR and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  . "${DOTFILES_DIR}/scripts/lib/dytoy_docs.sh"
  WITH="${BATS_TEST_TMPDIR}/browser.yaml.tmpl"
  cat > "${WITH}" << 'EOT'
{{- /* doc
name: firefox
description: Web browser
category: Browsers
subcategory: GUI
*/ -}}
{{- /* doc
name: zen
description: "Calm: `fast` browser"
category: Browsers
subcategory: GUI
*/ -}}
{{- if eq .os "linux" }}
firefox:
  repo: mozilla/firefox
{{- end }}
EOT
}

@test "blocks prints one document per block" {
  run dytoy_docs::blocks "${WITH}"
  assert_success
  local docs="${output}"
  run yq ea '[.name] | join(",")' <<< "${docs}"
  assert_output "firefox,zen"
  run yq ea '[.file] | join(",")' <<< "${docs}"
  assert_output "browser.yaml.tmpl,browser.yaml.tmpl"
}

@test "blocks prints nothing without a block" {
  printf 'firefox:\n  repo: a/b\n' > "${BATS_TEST_TMPDIR}/plain.yaml"
  run dytoy_docs::blocks "${BATS_TEST_TMPDIR}/plain.yaml"
  assert_success
  assert_output ""
}

@test "strip removes blocks and keeps the rest byte-identical" {
  cat > "${BATS_TEST_TMPDIR}/expected" << 'EOT'
{{- if eq .os "linux" }}
firefox:
  repo: mozilla/firefox
{{- end }}
EOT
  dytoy_docs::strip "${WITH}" > "${BATS_TEST_TMPDIR}/got"
  run dytoy_docs::strip "${WITH}"
  assert_output "$(< "${BATS_TEST_TMPDIR}/expected")"
  run cmp "${BATS_TEST_TMPDIR}/got" "${BATS_TEST_TMPDIR}/expected"
  assert_success
}
