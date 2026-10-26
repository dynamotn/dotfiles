#!/usr/bin/env bash
# @file log-agent.sh
# @brief PreToolUse hook recording every subagent spawn
# @description Append one JSON line per subagent Claude spawns to
# `${XDG_STATE_HOME:-~/.local/state}/claude/agent-usage.jsonl`, with its type
# and model, so it shows whether the expensive reasoning ran where it mattered
# and which subagents never fire:
#
#     jq -r '[.agent, .model] | @tsv' ~/.local/state/claude/agent-usage.jsonl | sort | uniq -c | sort -rn
#
# A spawn that names no subagent type runs the harness default, logged as
# general-purpose; one that names no model inherits the session's, logged as
# inherit. It only observes: it prints nothing and always exits 0, so it can
# never block or change a tool call.
set -euo pipefail

dir="${XDG_STATE_HOME:-${HOME}/.local/state}/claude"
input="$(cat)"
line="$(jq -c '{ts: (now | todate),
  agent: ((.tool_input.subagent_type // "") | if . == "" then "general-purpose" else . end),
  model: ((.tool_input.model // "") | if . == "" then "inherit" else . end),
  description: (.tool_input.description // ""), cwd: (.cwd // ""), session: (.session_id // "")}
  | select(.description != "" or .agent != "general-purpose")' <<< "${input}" 2> /dev/null || true)"
[[ -n "${line}" ]] || exit 0
mkdir -p -- "${dir}" 2> /dev/null || exit 0
printf '%s\n' "${line}" >> "${dir}/agent-usage.jsonl" 2> /dev/null || true
exit 0
