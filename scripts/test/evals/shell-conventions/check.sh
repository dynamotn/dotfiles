#!/usr/bin/env bash
# @file check.sh
# @brief Check the agent's bash helper follows the house conventions
# @description The library exists, parses, and carries a `# @description`.
set -euo pipefail
lib=scripts/lib/demo.sh
if [[ ! -f "${lib}" ]]; then
  printf '%s\n' "no ${lib}"
  exit 1
fi
if ! bash -n "${lib}"; then
  printf '%s\n' "${lib} does not parse"
  exit 1
fi
if ! grep -q '^# @description' "${lib}"; then
  printf '%s\n' "${lib} has no # @description comment"
  exit 1
fi
