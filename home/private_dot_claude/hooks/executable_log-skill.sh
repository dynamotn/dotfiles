#!/usr/bin/env bash
# @file log-skill.sh
# @brief PreToolUse hook recording every Skill invocation
# @description Append one JSON line per skill Claude invokes to
# `${XDG_STATE_HOME:-~/.local/state}/claude/skill-usage.jsonl`, so the skills
# that never fire, and the plugins that only cost context, show up over time:
#
#     jq -r .skill ~/.local/state/claude/skill-usage.jsonl | sort | uniq -c | sort -rn
#
# It only observes: it prints nothing and always exits 0, so it can never
# block or change a tool call.
set -euo pipefail

dir="${XDG_STATE_HOME:-${HOME}/.local/state}/claude"
input="$(cat)"
line="$(jq -c '{ts: (now | todate), skill: (.tool_input.skill // ""), cwd: (.cwd // ""),
  session: (.session_id // "")} | select(.skill != "")' <<< "${input}" 2> /dev/null || true)"
[[ -n "${line}" ]] || exit 0
mkdir -p -- "${dir}" 2> /dev/null || exit 0
printf '%s\n' "${line}" >> "${dir}/skill-usage.jsonl" 2> /dev/null || true
exit 0
