#!/usr/bin/env bash
# @file verify-on-stop.sh
# @brief Stop hook asking Claude to verify a change it has not checked yet
# @description Read the Stop hook input on stdin and look at the current turn
# of the transcript. When a file other than prose was edited after the last
# test, lint or render command of that turn, block the stop once with a
# reason, so Claude either runs the checks or says the work is unverified,
# as the machine-wide verification rules require. A second stop in the same
# chain (`stop_hook_active`) always passes, so the hook can never loop, and
# any failure to read the transcript passes too.
set -euo pipefail
((BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] >= 404)) || exit 0
shopt -s inherit_errexit

input="$(cat)"
active="$(jq -r '.stop_hook_active // false' <<< "${input}" 2> /dev/null || echo true)"
[[ "${active}" != "true" ]] || exit 0
transcript="$(jq -r '.transcript_path // ""' <<< "${input}" 2> /dev/null || true)"
[[ -n "${transcript}" && -f "${transcript}" ]] || exit 0

# Commands that count as checking the work: test runners, linters, type
# checkers, pre-commit, and the chezmoi render and diff previews.
checks='(^|[^[:alnum:]_-])(test\.sh|bats|pytest|jest|vitest|go (test|vet)|cargo (test|check|clippy)'
checks+='|(npm|pnpm|yarn|bun) (run )?(test|lint|check|typecheck)|make (test|check|lint)'
checks+='|dyshellint|shellcheck|prek|pre-commit|tox|nox|ruff|mypy|tsc|eslint'
checks+='|chezmoi (execute-template|diff))([^[:alnum:]_-]|$)'

# The last 4000 lines hold any realistic turn; a turn that started earlier is
# judged on what is left, which only makes the hook stricter.
# shellcheck disable=SC2016 # a jq program, its $names are jq variables
verdict="$(tail -n 4000 -- "${transcript}" | jq -rn --arg re "${checks}" '
  [inputs] as $all
  | def prompt: .type == "user" and (
      (.message.content | type) == "string"
      or ((.message.content | type) == "array" and any(.message.content[]; .type == "text")));
  ([$all | to_entries[] | select(.value | prompt) | .key] | last // -1) as $start
  | [$all[($start + 1):][] | select(.type == "assistant") | .message.content[]?
      | select(.type == "tool_use")] as $tools
  | ([$tools | to_entries[]
      | select(.value.name | test("^(Edit|Write|MultiEdit|NotebookEdit)$"))
      | select((.value.input.file_path // .value.input.notebook_path // "")
          | test("\\.(md|markdown|txt|rst)$") | not)] | last) as $edit
  | ([$tools | to_entries[]
      | select(.value.name == "Bash" and ((.value.input.command // "") | test($re)))
      | .key] | last // -1) as $check
  | if $edit != null and $check < $edit.key
    then ($edit.value.input.file_path // $edit.value.input.notebook_path // "a file")
    else "" end' 2> /dev/null || true)"
[[ -n "${verdict}" ]] || exit 0

jq -cn --arg f "${verdict}" '{
  decision: "block",
  reason: ("You changed " + $f + " after the last test or lint run of this turn. "
    + "Run the checks that cover it now, or say plainly in your reply that the "
    + "change is unverified and what the user has to run to confirm it.")
}'
