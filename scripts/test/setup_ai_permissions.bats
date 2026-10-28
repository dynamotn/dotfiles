# dyshellint disable=SC2154 BATS_TEST_TMPDIR and HOME come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  HOOK="${BATS_TEST_TMPDIR}/setup-ai.sh"
  render_template "home/.chezmoiscripts/run_onchange_after_03-setup-ai.sh.tmpl" "${HOOK}"
}

function _stub_agent {
  printf '#!/usr/bin/env bash\nexit 0\n' > "${HOME}/.local/bin/${1}"
  chmod +x "${HOME}/.local/bin/${1}"
}

# Claude-syntax rules, as dyai-data renders them: an exact and a `:*` git
# push (one prefix), a glued `*`, rtk spellings, and `rm -rf` in both lists.
function _write_config {
  dybatpho::ensure_dir "${HOME}/.config/dyai" > /dev/null
  cat > "${HOME}/.config/dyai/config.yaml" << 'EOF'
global:
  skills: []
  mcp: {}
  policy:
    permissions:
      ask:
        - "Bash(git push)"
        - "Bash(git push:*)"
        - "Bash(rtk git push *)"
        - "Bash(rtk run *)"
        - "Bash(rm -rf *)"
        - "Bash(sudo *)"
      deny:
        - "Bash(chezmoi-dycrypt*)"
        - "Bash(age -d *)"
        - "Bash(rm -rf *)"
        - "Bash(git * --force)"
        - "Read(**/secrets/data/**)"
        - "Read(**/.env)"
        - "Read(~/.ssh/**)"
        - "Edit(**/*.age)"
agents:
  claude: {}
EOF
}

# Run the hook twice and fail if the second run changed the file $1.
function _assert_idempotent {
  local before after
  before="$(< "${1}")"
  run bash "${HOOK}"
  assert_success
  after="$(< "${1}")"
  [[ "${before}" == "${after}" ]] || fail "second run changed ${1}"
}

@test "opencode: shell and path rules merge into permission, after the scalar default" {
  _stub_agent opencode
  dybatpho::ensure_dir "${HOME}/.config/opencode" > /dev/null
  printf '{"theme":"x","permission":{"bash":"ask","webfetch":"allow"}}' \
    > "${HOME}/.config/opencode/opencode.json"
  _write_config
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.config/opencode/opencode.json" got
  got="$(jq -c '.permission.bash' "${f}")"
  # The old scalar stays the "*" default, first, so the narrower keys win.
  jq -e --arg v "*" '.permission.bash | keys_unsorted[0] == $v' "${f}" > /dev/null
  jq -e --arg v "ask" '.permission.bash["*"] == $v' "${f}" > /dev/null
  jq -e --arg v "ask" '.permission.bash["git push"] == $v' "${f}" > /dev/null
  jq -e --arg v "ask" '.permission.bash["git push *"] == $v' "${f}" > /dev/null
  jq -e --arg v "deny" '.permission.bash["chezmoi-dycrypt*"] == $v' "${f}" > /dev/null
  jq -e --arg v "deny" '.permission.bash["age -d *"] == $v' "${f}" > /dev/null
  # Deny wins over ask for the same prefix; `rtk git` spellings are
  # Claude-only, while `rtk run` can run anything in any agent.
  jq -e --arg v "deny" '.permission.bash["rm -rf *"] == $v' "${f}" > /dev/null
  [[ "${got}" != *"rtk git"* ]] || fail "rtk git rule leaked: ${got}"
  jq -e --arg v "ask" '.permission.bash["rtk run *"] == $v' "${f}" > /dev/null
  # opencode matches globs, so a rule with an inner * carries over as is.
  jq -e --arg v "deny" '.permission.bash["git * --force"] == $v' "${f}" > /dev/null
  jq -e --arg v "deny" '.permission.read["*secrets/data/*"] == $v' "${f}" > /dev/null
  jq -e --arg v "deny" '.permission.read["*.env"] == $v' "${f}" > /dev/null
  jq -e --arg v "deny" '.permission.read["~/.ssh/*"] == $v' "${f}" > /dev/null
  jq -e --arg v "deny" '.permission.edit["*.age"] == $v' "${f}" > /dev/null
  jq -e --arg v "allow" '.permission.webfetch == $v' "${f}" > /dev/null
  jq -e --arg v "x" '.theme == $v' "${f}" > /dev/null
  _assert_idempotent "${f}"
}

@test "opencode: the accept-edits approval survives edit becoming a glob map" {
  _stub_agent opencode
  _write_config
  yq -i '.global.policy.approval = "accept-edits"' "${HOME}/.config/dyai/config.yaml"
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.config/opencode/opencode.json"
  jq -e --arg v "allow" '.permission.edit["*"] == $v' "${f}" > /dev/null
  jq -e --arg v "deny" '.permission.edit["*.age"] == $v' "${f}" > /dev/null
  _assert_idempotent "${f}"
}

@test "agy: shell rules merge into permissions as command(), user rules kept" {
  _stub_agent agy
  dybatpho::ensure_dir "${HOME}/.gemini/antigravity-cli" > /dev/null
  printf '{"permissions":{"allow":["command(ls)"],"deny":["command(mine)"]}}' \
    > "${HOME}/.gemini/antigravity-cli/settings.json"
  _write_config
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.gemini/antigravity-cli/settings.json"
  jq -e '.permissions.deny | index("command(chezmoi-dycrypt)") != null' "${f}" > /dev/null
  jq -e '.permissions.deny | index("command(rm -rf)") != null' "${f}" > /dev/null
  jq -e '.permissions.deny | index("command(mine)") != null' "${f}" > /dev/null
  jq -e '.permissions.ask | index("command(git push)") != null' "${f}" > /dev/null
  jq -e '.permissions.ask | index("command(rm -rf)") == null' "${f}" > /dev/null
  jq -e '.permissions.allow == ["command(ls)"]' "${f}" > /dev/null
  # Path rules have no documented glob form in agy, so none is written.
  jq -e '[.permissions[][] | select(startswith("read_file"))] | length == 0' "${f}" > /dev/null
  # A rule agy cannot match is dropped loudly, and a glued one is flagged.
  jq -e '[.permissions[][] | select(contains("*"))] | length == 0' "${f}" > /dev/null
  assert_output --partial 'agy: deny rule "git * --force" has an inner *'
  assert_output --partial 'agy: deny rule "chezmoi-dycrypt*" matches whole words'
  _assert_idempotent "${f}"
}

@test "gemini: a dyai-owned policy file denies above asking" {
  _stub_agent gemini
  _write_config
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.gemini/policies/dyai.toml" j
  j="$(yq -p=toml -o=json -I=0 '.' "${f}")"
  jq -e '.rule[] | select(.decision == "deny") | .commandPrefix | index("chezmoi-dycrypt") != null' \
    <<< "${j}" > /dev/null
  jq -e '.rule[] | select(.decision == "ask_user") | .commandPrefix == ["git push", "rtk run", "sudo"]' \
    <<< "${j}" > /dev/null
  jq -e '([.rule[] | select(.decision == "deny")][0].priority)
    > ([.rule[] | select(.decision == "ask_user")][0].priority)' <<< "${j}" > /dev/null
  jq -e '[.rule[].toolName] | unique == ["run_shell_command"]' <<< "${j}" > /dev/null
  jq -e '[.rule[].commandPrefix[] | select(contains("*"))] | length == 0' <<< "${j}" > /dev/null
  assert_output --partial 'gemini: deny rule "git * --force" has an inner *'
  # commandPrefix is a plain starts-with, so a glued rule loses nothing.
  refute_output --partial 'gemini: deny rule "chezmoi-dycrypt*"'
  _assert_idempotent "${f}"
}

@test "codex: a dyai-owned rules file forbids and prompts by token prefix" {
  _stub_agent codex
  _write_config
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.codex/rules/dyai.rules"
  grep -F 'prefix_rule(pattern = ["rm","-rf"], decision = "forbidden"' "${f}" > /dev/null
  grep -F 'prefix_rule(pattern = ["chezmoi-dycrypt"], decision = "forbidden"' "${f}" > /dev/null
  grep -F 'prefix_rule(pattern = ["git","push"], decision = "prompt"' "${f}" > /dev/null
  run grep -F '["rm","-rf"], decision = "prompt"' "${f}"
  assert_failure
  run grep -F '"*"' "${f}"
  assert_failure
  run bash "${HOOK}"
  assert_output --partial 'codex: deny rule "git * --force" has an inner *'
  assert_output --partial 'codex: deny rule "chezmoi-dycrypt*" matches whole words'
  _assert_idempotent "${f}"
}

@test "hermes: deny rules merge into approvals.deny, other keys kept" {
  _stub_agent hermes
  dybatpho::ensure_dir "${HOME}/.hermes" > /dev/null
  printf 'model: x\napprovals:\n  mode: manual\n  deny:\n    - "mine*"\n' > "${HOME}/.hermes/config.yaml"
  _write_config
  run bash "${HOOK}"
  assert_success
  local f="${HOME}/.hermes/config.yaml"
  yq -e '.model == "x"' "${f}" > /dev/null
  yq -e '.approvals.mode == "manual"' "${f}" > /dev/null
  yq -e '.approvals.deny[] | select(. == "mine*")' "${f}" > /dev/null
  yq -e '.approvals.deny[] | select(. == "chezmoi-dycrypt*")' "${f}" > /dev/null
  yq -e '.approvals.deny[] | select(. == "age -d *")' "${f}" > /dev/null
  yq -e '.approvals.deny[] | select(. == "rm -rf")' "${f}" > /dev/null
  yq -e '.approvals.deny[] | select(. == "git * --force")' "${f}" > /dev/null
  # Hermes has no ask list, so git push (ask only) is not denied.
  run yq -e '.approvals.deny[] | select(. == "git push *")' "${f}"
  assert_failure
  _assert_idempotent "${f}"
}

@test "no permission rules writes no agent file" {
  _stub_agent gemini
  _stub_agent codex
  _write_config
  yq -i 'del(.global.policy.permissions)' "${HOME}/.config/dyai/config.yaml"
  run bash "${HOOK}"
  assert_success
  [[ ! -e "${HOME}/.gemini/policies/dyai.toml" ]]
  [[ ! -e "${HOME}/.codex/rules/dyai.rules" ]]
}
