#!/usr/bin/env bash
# @file route-agent.sh
# @brief Require a routing decision before Claude spawns a subagent
# @description Two modes, one per hook:
#
# - `record` (PostToolUse on the laya routing tools) notes that this session
#   asked laya which model a job needs, in
#   `${XDG_STATE_HOME:-~/.local/state}/claude/agent-routes.jsonl`.
# - `gate` (PreToolUse on Agent and Task) lets a spawn through when it is
#   routed: it names a `model`, it is a `fork` (which keeps the parent's
#   model), or the session recorded a routing call in the last 15 minutes.
#   Otherwise it denies the spawn, with the reason telling the agent how to
#   route it. `DYAI_AGENT_ROUTING=warn` allows and only adds that text;
#   `off`, or a crew worker (`DYAI_CREW` set), turns the gate off.
#
# Input that does not parse is let through: the gate must never wedge a
# session on garbage. `record` prints nothing and always exits 0.
set -euo pipefail

mode="${1:-gate}"
dir="${XDG_STATE_HOME:-${HOME}/.local/state}/claude"
ledger="${dir}/agent-routes.jsonl"
input="$(cat)"
session="$(jq -r '.session_id // "" | strings' <<< "${input}" 2> /dev/null)" || exit 0
now="$(date +%s)"

if [[ "${mode}" == record ]]; then
  [[ -n "${session}" ]] || exit 0
  mkdir -p -- "${dir}" 2> /dev/null || exit 0
  jq -cn --argjson ts "${now}" --arg s "${session}" '{ts: $ts, session: $s}' >> "${ledger}" 2> /dev/null || true
  exit 0
fi

routing="${DYAI_AGENT_ROUTING:-block}"
[[ "${routing}" != off && -z "${DYAI_CREW:-}" ]] || exit 0
routed="$(jq -r '(.tool_input.model // "" | strings | length > 0)
  or ((.tool_input.subagent_type // "") == "fork")' <<< "${input}" 2> /dev/null)" || exit 0
[[ "${routed}" != true ]] || exit 0
if [[ -n "${session}" ]] && [[ -f "${ledger}" ]] \
  && jq -e --arg s "${session}" --argjson since "$((now - 900))" \
    'select(.session == $s and .ts >= $since)' "${ledger}" &> /dev/null; then
  exit 0
fi

reason="Pick the model for this subagent before spawning it: set model (haiku for search, lookups and"
reason+=" summaries, sonnet for routine coding, opus for review, security and design judgments), or call"
reason+=" laya_route first. A fork keeps your model and needs neither."
if [[ "${routing}" == warn ]]; then
  jq -cn --arg r "${reason}" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $r}}'
else
  jq -cn --arg r "${reason}" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
fi
exit 0
