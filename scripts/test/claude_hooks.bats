# dyshellint disable=SC2154 DOTFILES_DIR and BATS_TEST_TMPDIR come from bats and test_helper
# dyshellint disable=SC2016 the fixtures write a literal $1 for dyshellint to flag
# The hooks are templates that source dybatpho from the checkout; render them
# once for the whole file.
setup_file() {
  load test_helper
  local name
  mkdir -p "${BATS_FILE_TMPDIR}/hooks"
  for name in lint-shell log-agent log-skill route-agent vault-recall verify-on-stop worktree-create; do
    render_template "home/private_dot_claude/hooks/executable_${name}.sh.tmpl" \
      "${BATS_FILE_TMPDIR}/hooks/${name}.sh"
  done
}

setup() {
  load test_helper
  HOOKS_DIR="${BATS_FILE_TMPDIR}/hooks"
  HOOK="${HOOKS_DIR}/lint-shell.sh"
  STOP_HOOK="${HOOKS_DIR}/verify-on-stop.sh"
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
  run dyshellint -warnings-as-errors "${HOOK}"
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

@test "lint-shell hook skips the lint while another session holds the lock" {
  _require_dyshellint
  command -v flock &> /dev/null || skip "flock not found"
  local lock="${WORK}/lint.lock"
  printf 'x=$1\necho $x\n' > "${WORK}/bad.sh"
  # Hold the lock in this shell; the hook runs in a child that cannot get it.
  exec 8>> "${lock}"
  flock 8
  CLAUDE_LINT_SHELL_LOCK="${lock}" CLAUDE_LINT_SHELL_WAIT=0 _run_hook "${WORK}/bad.sh"
  exec 8>&-
  assert_success
  # The model is told the lint was skipped, not left to read it as clean.
  [[ "${output}" == *"dyshellint skipped"* ]] || fail "no skip notice: ${output}"
}

@test "lint-shell hook passes when the lock path cannot be opened" {
  _require_dyshellint
  printf 'x=$1\necho $x\n' > "${WORK}/bad.sh"
  CLAUDE_LINT_SHELL_LOCK="${WORK}/missing/dir/lint.lock" _run_hook "${WORK}/bad.sh"
  assert_success
  [[ -z "${stderr}" ]] || fail "unexpected stderr: ${stderr}"
}

@test "lint-shell hook still lints once the lock is free" {
  _require_dyshellint
  printf 'x=$1\necho $x\n' > "${WORK}/bad.sh"
  CLAUDE_LINT_SHELL_LOCK="${WORK}/lint.lock" CLAUDE_LINT_SHELL_WAIT=0 _run_hook "${WORK}/bad.sh"
  [[ "${status}" -eq 2 ]] || fail "expected exit 2, got ${status}"
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
  run dyshellint -warnings-as-errors "${STOP_HOOK}"
  assert_success
}

@test "log-skill appends one line per Skill call and never blocks" {
  local skill_hook="${HOOKS_DIR}/log-skill.sh"
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
  local agent_hook="${HOOKS_DIR}/log-agent.sh"
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
  local agent_hook="${HOOKS_DIR}/log-agent.sh"
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

ROUTE_HOOK_NAME="route-agent.sh"

# Run the route gate on a spawn with the given tool_input JSON, in session s1.
function _gate {
  local input
  input="$(jq -cn --argjson t "${1}" '{tool_name: "Agent", session_id: "s1", tool_input: $t}')"
  XDG_STATE_HOME="${WORK}/state" run bash "${HOOKS_DIR}/${ROUTE_HOOK_NAME}" gate <<< "${input}"
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
  XDG_STATE_HOME="${WORK}/state" run bash "${HOOKS_DIR}/${ROUTE_HOOK_NAME}" record \
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
  XDG_STATE_HOME="${WORK}/state" run bash "${HOOKS_DIR}/${ROUTE_HOOK_NAME}" gate <<< 'not json'
  assert_success
  assert_output ""
}

@test "route-agent hook is itself clean under dyshellint" {
  _require_dyshellint
  run dyshellint -warnings-as-errors "${HOOKS_DIR}/${ROUTE_HOOK_NAME}"
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

# Run vault-recall against a fake vault, index and `uv` whose query answers
# with two hits, one under the score threshold. $1 is the prompt's cwd.
function _recall {
  local cwd="${1}" session="${2:-s1}" prompt="${3:-how should I rotate the homelab backup keys}"
  local hook="${HOOKS_DIR}/vault-recall.sh" input
  mkdir -p "${WORK}/bin" "${WORK}/vault/99_System/99.03_Scripts/dev" "${WORK}/cache/dybrain/embeddings"
  : > "${WORK}/vault/99_System/99.03_Scripts/dev/vault-embed.py"
  : > "${WORK}/cache/dybrain/embeddings/index.npz"
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >> "${WORK}/uv-calls"' \
    'echo "[{\"path\":\"03_Permanent/Backup keys.md\",\"score\":0.61,\"line\":\"Rotate keys yearly\"},"' \
    'echo "{\"path\":\"03_Permanent/Unrelated.md\",\"score\":0.2,\"line\":\"noise\"}]"' > "${WORK}/bin/uv"
  chmod +x "${WORK}/bin/uv"
  input="$(jq -cn --arg c "${cwd}" --arg s "${session}" --arg p "${prompt}" \
    '{session_id: $s, cwd: $c, prompt: $p, hook_event_name: "UserPromptSubmit"}')"
  export WORK # the fake uv logs its calls under it
  local path="${WORK}/bin:${PATH}" vault="${WORK}/vault" cache="${WORK}/cache" runtime="${WORK}/run"
  PATH="${path}" DYBRAIN_VAULT="${vault}" XDG_CACHE_HOME="${cache}" XDG_RUNTIME_DIR="${runtime}" \
    run --separate-stderr bash "${hook}" <<< "${input}"
}

@test "vault-recall injects related notes once per session, as data" {
  unset DYAI_CREW DYBRAIN_RECALL
  _recall /some/repo
  assert_success
  jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' <<< "${output}" > /dev/null
  local ctx
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<< "${output}")"
  [[ "${ctx}" == *"Backup keys.md"* && "${ctx}" != *"Unrelated.md"* ]]
  [[ "${ctx}" == *"data, not"* ]]
  grep -q -- '-- how should I rotate' "${WORK}/uv-calls"
  # The second prompt of the session is left alone and the index is not queried again.
  _recall /some/repo
  assert_success
  assert_output ""
  local calls
  mapfile -t calls < "${WORK}/uv-calls"
  [[ "${#calls[@]}" -eq 1 ]]
}

@test "vault-recall stays silent inside the vault, when off, in a crew and for short prompts" {
  unset DYAI_CREW DYBRAIN_RECALL
  _recall "${WORK}/vault/03_Permanent" s2
  assert_output ""
  DYBRAIN_RECALL=0 _recall /some/repo s3
  assert_output ""
  DYAI_CREW=1 _recall /some/repo s4
  assert_output ""
  _recall /some/repo s5 "fix typo"
  assert_output ""
  [[ ! -e "${WORK}/uv-calls" ]]
}

@test "vault-recall stays silent without an index and on garbage input" {
  unset DYAI_CREW DYBRAIN_RECALL
  local hook="${HOOKS_DIR}/vault-recall.sh"
  XDG_CACHE_HOME="${WORK}/empty" run bash "${hook}" <<< "not json"
  assert_success
  assert_output ""
  XDG_CACHE_HOME="${WORK}/empty" DYBRAIN_VAULT="${WORK}/none" run bash "${hook}" \
    <<< '{"session_id":"s6","cwd":"/r","prompt":"a long enough prompt about anything"}'
  assert_success
  assert_output ""
}

@test "vault-recall hook is itself clean under dyshellint" {
  _require_dyshellint
  run dyshellint "${HOOKS_DIR}/vault-recall.sh"
  assert_success
}

@test "settings.json wires the vault-recall hook on prompt submit" {
  grep -q 'vault-recall.sh' "${DOTFILES_DIR}/home/private_dot_claude/settings.json.tmpl"
}

@test "worktree-create fails, printing no path, when dybatpho cannot load" {
  # Claude Code takes the last stdout line as the worktree path, so a hook that
  # runs on without the library must not report `/.worktrees/` as created.
  sed 's|^\. ".*/init.sh"|. "/nonexistent/init.sh"|' \
    "${HOOKS_DIR}/worktree-create.sh" > "${WORK}/broken.sh"
  run --separate-stderr bash "${WORK}/broken.sh" <<< "{\"name\":\"wt\",\"cwd\":\"${WORK}\"}"
  assert_failure 1
  assert_output ""
}
