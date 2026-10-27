# dyshellint disable=SC2154 DOTFILES_DIR and BATS_TEST_TMPDIR come from bats and test_helper
# dyshellint disable=SC2016 the fixtures write a literal $1 for dyshellint to flag
setup() {
  load test_helper
  HOOK="${DOTFILES_DIR}/home/private_dot_claude/hooks/executable_lint-shell.sh"
  STOP_HOOK="${DOTFILES_DIR}/home/private_dot_claude/hooks/executable_verify-on-stop.sh"
  WORK="${BATS_TEST_TMPDIR}/work"
  mkdir -p "${WORK}"
}

function _require_dyshellint {
  command -v dyshellint &> /dev/null || skip "dyshellint not found"
}

# Feed the hook the PostToolUse input of an edit of $1.
function _run_hook {
  local input
  input="$(jq -cn --arg f "${1}" '{tool_input: {file_path: $f}}')"
  run --separate-stderr bash "${HOOK}" <<< "${input}"
}

@test "lint-shell hook is itself clean under dyshellint" {
  _require_dyshellint
  # The source carries chezmoi's executable_ prefix instead of the bit.
  run dyshellint -warnings-as-errors -exclude-rules BSG037 "${HOOK}"
  assert_success
}

@test "lint-shell hook reports warnings, not only errors" {
  _require_dyshellint
  printf '#!/usr/bin/env bash\n# @file w.sh\n# @brief W\n# @description W.\nset -euo pipefail\nx="a"\necho "$x"\n' \
    > "${WORK}/warn.sh"
  chmod +x "${WORK}/warn.sh"
  run dyshellint "${WORK}/warn.sh"
  # Precondition: dyshellint alone passes this file with warnings only.
  assert_success
  _run_hook "${WORK}/warn.sh"
  [[ "${status}" -eq 2 ]] || fail "expected exit 2, got ${status}"
}

@test "lint-shell hook feeds dyshellint findings back with exit 2" {
  _require_dyshellint
  printf 'x=$1\necho $x\n' > "${WORK}/bad.sh"
  _run_hook "${WORK}/bad.sh"
  [[ "${status}" -eq 2 ]] || fail "expected exit 2, got ${status}"
  [[ "${stderr}" == *"dyshellint reported new findings"* ]]
  [[ "${stderr}" == *"SC2086"* ]]
}

@test "lint-shell hook passes a clean script silently" {
  _require_dyshellint
  _run_hook "${HOOK}"
  assert_success
  [[ -z "${stderr}" ]]
}

@test "lint-shell hook recognizes an extensionless script by its shebang" {
  _require_dyshellint
  printf '#!/usr/bin/env bash\necho $1\n' > "${WORK}/tool"
  _run_hook "${WORK}/tool"
  [[ "${status}" -eq 2 ]] || fail "expected exit 2, got ${status}"
}

@test "lint-shell hook ignores templates, other files and missing paths" {
  _require_dyshellint
  printf 'echo {{ .x }} $1\n' > "${WORK}/a.sh.tmpl"
  printf '# notes $1\n' > "${WORK}/notes.md"
  local f
  for f in "${WORK}/a.sh.tmpl" "${WORK}/notes.md" "${WORK}/missing.sh"; do
    _run_hook "${f}"
    assert_success
  done
}

# A git repo whose committed legacy.sh already carries an unquoted $1.
# dyshellint disable=BSG062 test_helper unsets GIT_DIR and its kin for the whole suite
function _legacy_repo {
  local repo="${WORK}/repo"
  mkdir -p "${repo}"
  git -C "${repo}" init -q
  printf '#!/usr/bin/env bash\necho $1\n' > "${repo}/legacy.sh"
  git -C "${repo}" add legacy.sh
  git -C "${repo}" -c user.name=t -c user.email=t@t commit -qm init
}

@test "lint-shell hook ignores findings the committed version already had" {
  _require_dyshellint
  _legacy_repo
  # The edit moves the old finding down a line and adds nothing new.
  printf '#!/usr/bin/env bash\ntrue\necho $1\n' > "${WORK}/repo/legacy.sh"
  _run_hook "${WORK}/repo/legacy.sh"
  assert_success
}

@test "lint-shell hook reports only the findings an edit introduced" {
  _require_dyshellint
  _legacy_repo
  printf '#!/usr/bin/env bash\necho $1\ncd /tmp\n' > "${WORK}/repo/legacy.sh"
  _run_hook "${WORK}/repo/legacy.sh"
  [[ "${status}" -eq 2 ]] || fail "expected exit 2, got ${status}"
  [[ "${stderr}" == *"legacy.sh:3:"* ]] || fail "new finding missing: ${stderr}"
  [[ "${stderr}" != *"legacy.sh:2:"* ]] || fail "old finding reported: ${stderr}"
}

@test "lint-shell hook never runs a program the edited repo's git config names" {
  _require_dyshellint
  _legacy_repo
  local marker="${WORK}/pwned"
  printf '#!/bin/sh\ntouch %s\n' "${marker}" > "${WORK}/evil"
  chmod +x "${WORK}/evil"
  git -C "${WORK}/repo" config core.fsmonitor "${WORK}/evil"
  # Precondition: plain git in this repo does run it.
  git -C "${WORK}/repo" status > /dev/null 2>&1 || true
  [[ -e "${marker}" ]] || skip "this git does not run core.fsmonitor"
  rm -f -- "${marker}"
  printf '#!/usr/bin/env bash\necho $1\ncd /tmp\n' > "${WORK}/repo/legacy.sh"
  _run_hook "${WORK}/repo/legacy.sh"
  [[ ! -e "${marker}" ]] || fail "the hook ran the repo's core.fsmonitor"
}

@test "lint-shell hook is a no-op without dyshellint on PATH" {
  printf 'echo $1\n' > "${WORK}/bad.sh"
  PATH="/usr/bin:/bin" _run_hook "${WORK}/bad.sh"
  assert_success
}

# Transcript lines, in Claude Code's JSONL shape.
function _prompt { jq -cn --arg t "${1}" '{type: "user", message: {content: $t}}'; }
function _edit {
  jq -cn --arg f "${1}" '{type: "assistant", message: {content: [
    {type: "tool_use", name: "Edit", input: {file_path: $f}}]}}'
}
function _bash {
  jq -cn --arg c "${1}" '{type: "assistant", message: {content: [
    {type: "tool_use", name: "Bash", input: {command: $c}}]}}'
}
function _result { printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result"}]}}'; }

# Run the Stop hook against the transcript $1, with stop_hook_active $2.
function _run_stop {
  local input
  input="$(jq -cn --arg t "${1}" --argjson a "${2:-false}" '{transcript_path: $t, stop_hook_active: $a}')"
  run --separate-stderr bash "${STOP_HOOK}" <<< "${input}"
}

@test "verify-on-stop blocks once when an edit follows the last check" {
  local t="${WORK}/t.jsonl"
  {
    _prompt "fix it"
    _bash "./scripts/test.sh --all"
    _result
    _edit "/r/lib.sh"
    _result
  } > "${t}"
  _run_stop "${t}"
  assert_success
  jq -e '.decision == "block" and (.reason | contains("/r/lib.sh"))' <<< "${output}" > /dev/null \
    || fail "expected a block naming the file, got: ${output}"
  # The continued stop always passes, so the hook cannot loop.
  _run_stop "${t}" true
  assert_success
  assert_output ""
}

@test "verify-on-stop passes when a check ran after the last edit" {
  local t="${WORK}/t.jsonl"
  {
    _prompt "fix it"
    _edit "/r/lib.sh"
    _result
    _bash "dyshellint /r/lib.sh"
    _result
  } > "${t}"
  _run_stop "${t}"
  assert_success
  assert_output ""
}

@test "verify-on-stop ignores prose edits and edits of an earlier turn" {
  local t="${WORK}/t.jsonl"
  {
    _prompt "docs"
    _edit "/r/README.md"
    _result
  } > "${t}"
  _run_stop "${t}"
  assert_output ""
  {
    _prompt "fix"
    _edit "/r/lib.sh"
    _result
    _prompt "thanks, what next?"
  } > "${t}"
  _run_stop "${t}"
  assert_output ""
}

@test "verify-on-stop passes on a missing or unreadable transcript" {
  _run_stop "${WORK}/none.jsonl"
  assert_success
  assert_output ""
  printf 'not json\n' > "${WORK}/bad.jsonl"
  _run_stop "${WORK}/bad.jsonl"
  assert_success
  assert_output ""
}

@test "verify-on-stop hook is itself clean under dyshellint" {
  _require_dyshellint
  run dyshellint -warnings-as-errors -exclude-rules BSG037 "${STOP_HOOK}"
  assert_success
}

@test "log-skill appends one line per Skill call and never blocks" {
  local skill_hook="${DOTFILES_DIR}/home/private_dot_claude/hooks/executable_log-skill.sh"
  local state="${WORK}/state" input
  input='{"tool_name":"Skill","tool_input":{"skill":"dybatpho"},"cwd":"/r","session_id":"s1"}'
  XDG_STATE_HOME="${state}" run bash "${skill_hook}" <<< "${input}"
  assert_success
  assert_output ""
  jq -e '.skill == "dybatpho" and .cwd == "/r" and .session == "s1"' \
    "${state}/claude/skill-usage.jsonl" > /dev/null
  # Garbage in, nothing written, still exit 0.
  XDG_STATE_HOME="${state}" run bash "${skill_hook}" <<< "not json"
  assert_success
  local lines
  mapfile -t lines < "${state}/claude/skill-usage.jsonl"
  [[ "${#lines[@]}" -eq 1 ]]
}

@test "settings.json wires the stop and skill hooks" {
  local tmpl="${DOTFILES_DIR}/home/private_dot_claude/settings.json.tmpl"
  grep -q 'verify-on-stop.sh' "${tmpl}"
  grep -q 'log-skill.sh' "${tmpl}"
}

@test "log-agent records type and model and never blocks" {
  local agent_hook="${DOTFILES_DIR}/home/private_dot_claude/hooks/executable_log-agent.sh"
  local state="${WORK}/state" input
  input='{"tool_name":"Agent","session_id":"s1",
    "tool_input":{"subagent_type":"Explore","model":"haiku","description":"x"}}'
  XDG_STATE_HOME="${state}" run bash "${agent_hook}" <<< "${input}"
  assert_success
  assert_output ""
  jq -e '.agent == "Explore" and .model == "haiku" and .session == "s1"' \
    "${state}/claude/agent-usage.jsonl" > /dev/null
  # No type and no model: the harness default and the session's model.
  XDG_STATE_HOME="${state}" run bash "${agent_hook}" <<< '{"tool_input":{"description":"y"}}'
  assert_success
  jq -se '.[1].agent == "general-purpose" and .[1].model == "inherit"' \
    "${state}/claude/agent-usage.jsonl" > /dev/null
}

@test "log-agent never fails on garbage input" {
  local agent_hook="${DOTFILES_DIR}/home/private_dot_claude/hooks/executable_log-agent.sh"
  local state="${WORK}/state"
  XDG_STATE_HOME="${state}" run bash "${agent_hook}" <<< "not json"
  assert_success
  assert_output ""
  [[ ! -e "${state}/claude/agent-usage.jsonl" ]]
}

@test "settings.json wires the log-agent hook on subagent spawns" {
  local tmpl="${DOTFILES_DIR}/home/private_dot_claude/settings.json.tmpl"
  grep -q 'log-agent.sh' "${tmpl}"
}

@test "settings.json wires the lint-shell hook on Edit and Write" {
  local tmpl="${DOTFILES_DIR}/home/private_dot_claude/settings.json.tmpl"
  grep -q 'lint-shell.sh' "${tmpl}"
}

ROUTE_HOOK_REL="home/private_dot_claude/hooks/executable_route-agent.sh"

# Run the route gate on a spawn with the given tool_input JSON, in session s1.
function _gate {
  local input
  input="$(jq -cn --argjson t "${1}" '{tool_name: "Agent", session_id: "s1", tool_input: $t}')"
  XDG_STATE_HOME="${WORK}/state" run bash "${DOTFILES_DIR}/${ROUTE_HOOK_REL}" gate <<< "${input}"
}

# Record a routing call for session $1, $2 seconds ago.
function _routed {
  local now
  now="$(date +%s)"
  mkdir -p "${WORK}/state/claude"
  jq -cn --arg s "${1}" --argjson ts "$((now - ${2:-0}))" '{ts: $ts, session: $s}' \
    >> "${WORK}/state/claude/agent-routes.jsonl"
}

@test "route gate denies a spawn with no model and no routing call" {
  unset DYAI_AGENT_ROUTING DYAI_CREW
  _gate '{"subagent_type":"Explore","description":"x"}'
  assert_success
  local filter='.hookSpecificOutput | .permissionDecision + " "'
  filter+=' + (.permissionDecisionReason | test("model"; "i") | tostring)'
  run jq -r "${filter}" <<< "${output}"
  assert_output "deny true"
}

@test "route gate allows an explicit model and a fork" {
  unset DYAI_AGENT_ROUTING DYAI_CREW
  _gate '{"subagent_type":"Explore","model":"haiku","description":"x"}'
  assert_success
  assert_output ""
  _gate '{"subagent_type":"fork","description":"x"}'
  assert_output ""
}

@test "route gate allows after a recent routing call in the same session only" {
  unset DYAI_AGENT_ROUTING DYAI_CREW
  _routed s1 60
  _gate '{"description":"x"}'
  assert_output ""
  rm -f "${WORK}/state/claude/agent-routes.jsonl"
  _routed other 0
  _routed s1 3600
  _gate '{"description":"x"}'
  run jq -r .hookSpecificOutput.permissionDecision <<< "${output}"
  assert_output "deny"
}

@test "route record notes the session of a laya routing call and prints nothing" {
  XDG_STATE_HOME="${WORK}/state" run bash "${DOTFILES_DIR}/${ROUTE_HOOK_REL}" record \
    <<< '{"tool_name":"mcp__laya__laya_route","session_id":"s9"}'
  assert_success
  assert_output ""
  jq -e '.session == "s9" and (.ts | type) == "number"' "${WORK}/state/claude/agent-routes.jsonl" > /dev/null
}

@test "route gate warns instead with DYAI_AGENT_ROUTING=warn, and stays out with off or in a crew task" {
  DYAI_AGENT_ROUTING=warn _gate '{"description":"x"}'
  local filter='.hookSpecificOutput | (.permissionDecision // "none") + " "'
  filter+=' + (.additionalContext | test("model") | tostring)'
  run jq -r "${filter}" <<< "${output}"
  assert_output "none true"
  DYAI_AGENT_ROUTING=off _gate '{"description":"x"}'
  assert_output ""
  DYAI_CREW=x _gate '{"description":"x"}'
  assert_output ""
}

@test "route gate allows garbage input" {
  XDG_STATE_HOME="${WORK}/state" run bash "${DOTFILES_DIR}/${ROUTE_HOOK_REL}" gate <<< 'not json'
  assert_success
  assert_output ""
}

@test "route-agent hook is itself clean under dyshellint" {
  _require_dyshellint
  run dyshellint -warnings-as-errors -exclude-rules BSG037 "${DOTFILES_DIR}/${ROUTE_HOOK_REL}"
  assert_success
}

@test "settings.json wires the route gate on spawns and the recorder on laya routing" {
  local tmpl="${DOTFILES_DIR}/home/private_dot_claude/settings.json.tmpl"
  grep -q 'route-agent.sh gate' "${tmpl}"
  grep -q 'route-agent.sh record' "${tmpl}"
  grep -q 'mcp__laya__laya_route' "${tmpl}"
}

@test "route gate allows a subagent whose definition pins a model" {
  unset DYAI_AGENT_ROUTING DYAI_CREW
  mkdir -p "${WORK}/claude/agents"
  printf -- '---\nname: pinned\nmodel: haiku\n---\nbody\n' > "${WORK}/claude/agents/pinned.md"
  printf -- '---\nname: loose\nmodel: inherit\n---\nbody\n' > "${WORK}/claude/agents/loose.md"
  CLAUDE_CONFIG_DIR="${WORK}/claude" _gate '{"subagent_type":"pinned","description":"x"}'
  assert_output ""
  CLAUDE_CONFIG_DIR="${WORK}/claude" _gate '{"subagent_type":"loose","description":"x"}'
  run jq -r .hookSpecificOutput.permissionDecision <<< "${output}"
  assert_output deny
}
