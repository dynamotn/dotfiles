#!/usr/bin/env bash
# @file lint-shell.sh
# @brief PostToolUse hook running dyshellint on a shell script Claude just wrote
# @description Read the Edit/Write hook input on stdin and, when the file is a
# bash script, lint it with dyshellint. Findings go to stderr with exit code 2,
# which Claude Code feeds back to the model so it fixes them in the same turn.
# Anything that is not a lintable shell script, or a machine without
# dyshellint, passes silently: a hook must never block an unrelated edit.
set -euo pipefail

command -v dyshellint &> /dev/null || exit 0
file="$(jq -r '.tool_input.file_path // ""')"
[[ -n "${file}" && -f "${file}" ]] || exit 0

case "${file}" in
  # Go templates are not valid shell until chezmoi renders them.
  *.tmpl) exit 0 ;;
  *.sh | *.bash | *.bats) ;;
  *)
    # An extensionless script is recognized by its shebang.
    head -n 1 -- "${file}" | grep -qE '^#!.*\b(ba)?sh\b' || exit 0
    ;;
esac

# Warnings count too: the machine rules say to fix whatever dyshellint reports.
args=(-warnings-as-errors)
# A chezmoi `executable_` source is stored without the bit; apply sets it.
[[ "$(basename -- "${file}")" != executable_* ]] || args+=(-exclude-rules BSG037)

if output="$(dyshellint "${args[@]}" "${file}" 2>&1)"; then
  exit 0
fi
printf 'dyshellint reported findings in %s; fix them before reporting done:\n%s\n' \
  "${file}" "${output}" >&2
exit 2
