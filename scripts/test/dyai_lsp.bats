setup() {
  load test_helper
  setup_dotfiles_test_env
  # shellcheck disable=SC2154 # DOTFILES_DIR is set by test_helper.bash
  . "${DOTFILES_DIR}/scripts/lib/dyai.sh"
  export XDG_CACHE_HOME="${HOME}/.cache"
  FIXTURES="${DOTFILES_DIR}/scripts/test/fixtures/dyai-lsp"
  export DYAI_NVIM_CONFIG="${FIXTURES}/nvim"
  export DYAI_LSPCONFIG_DIR="${FIXTURES}/lspconfig"
  # shellcheck disable=SC2154 # BATS_TEST_TMPDIR is set by bats itself
  export DYAI_MASON_BIN="${BATS_TEST_TMPDIR}/mason_bin"
  mkdir -p "${DYAI_MASON_BIN}"
  for bin in pyls-bin ruff-bin fakels-bin; do
    printf '#!/usr/bin/env bash\n' > "${DYAI_MASON_BIN}/${bin}"
    chmod +x "${DYAI_MASON_BIN}/${bin}"
  done
  # Ruling 2: the exporter reads the exclude list from CONFIG_FILE's
  # global.lsp.exclude; genericls is excluded there, not in the fixture.
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${HOME}/.config/dyai/config.yaml" << 'CFG'
global:
  lsp:
    exclude: [genericls]
CFG
  export CONFIG_FILE="${HOME}/.config/dyai/config.yaml"
}

@test "dyai_lsp::export writes servers in languages.lua order with resolved commands" {
  # python = {pyls, ruffls}; fake = {fakels}; generic = {genericls}
  # genericls is in the exclude list; fnls has a function cmd
  dyai_lsp::export
  m="${XDG_CACHE_HOME}/dyai/lsp.json"
  # shellcheck disable=SC2312 # a bad export left the manifest absent; jq fails and so does the comparison
  [[ "$(jq -r '[.servers[].name] | join(",")' "${m}")" == "pyls,ruffls,fakels" ]]
  # shellcheck disable=SC2312 # a bad export left the manifest absent; jq fails and so does the comparison
  [[ "$(jq -r '.servers[0].command' "${m}")" == "${DYAI_MASON_BIN}/pyls-bin" ]]
  # shellcheck disable=SC2312 # a bad export left the manifest absent; jq fails and so does the comparison
  [[ "$(jq -r '.servers[0].extensions[".py"]' "${m}")" == "python" ]]
}

@test "dyai_lsp::export applies lsp/*.lua and plugins/lang cmd and settings overrides" {
  # fixture lsp/fakels.lua sets cmd {'fakels-bin','--stdio'};
  # lang/fake.lua sets opts.servers.fakels.settings = { fake = { on = true } }
  dyai_lsp::export
  m="${XDG_CACHE_HOME}/dyai/lsp.json"
  # shellcheck disable=SC2312 # a bad export left the manifest absent; jq fails and so does the comparison
  [[ "$(jq -c '.servers[] | select(.name=="fakels") | .args' "${m}")" == '["--stdio"]' ]]
  # shellcheck disable=SC2312 # a bad export left the manifest absent; jq fails and so does the comparison
  [[ "$(jq -c '.servers[] | select(.name=="fakels") | .settings' "${m}")" == '{"fake":{"on":true}}' ]]
}

@test "dyai_lsp::export converts review.lua hold patterns to ERE" {
  dyai_lsp::export
  # shellcheck disable=SC2312 # a bad export left the manifest absent; jq fails and so does the comparison
  [[ "$(jq -r '.untrusted_regexes[0]' "${XDG_CACHE_HOME}/dyai/lsp.json")" == '^(.*/\.worktrees/dyreview-[^/]+)(/|$)' ]]
}

@test "dyai_lsp::export keeps the old manifest when nvim is missing" {
  dybatpho::ensure_dir "${XDG_CACHE_HOME}/dyai" > /dev/null
  printf '{"version":1,"servers":[]}' > "${XDG_CACHE_HOME}/dyai/lsp.json"
  DYAI_NVIM="${BATS_TEST_TMPDIR}/no-such-nvim" run dyai_lsp::export
  assert_failure
  # shellcheck disable=SC2312 # a missing file would fail cat, and the comparison with it
  [[ "$(cat "${XDG_CACHE_HOME}/dyai/lsp.json")" == '{"version":1,"servers":[]}' ]]
}
