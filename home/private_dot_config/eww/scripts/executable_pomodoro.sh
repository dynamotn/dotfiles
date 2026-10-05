#!/usr/bin/env bash
# @file pomodoro.sh
# @brief Report the current pomodoro state for the eww bar
# @description Report the running state, the remaining time, the cycle count and
# the phase label of the current pomodoro as one JSON object, so the bar reads
# every field from a single call instead of one poll per field.
set -euo pipefail

# @description Print the pomodoro state as a JSON object.
# @noargs
# @stdout One JSON object.
function _main {
  local label

  label="$(pomodoro status -f '%L' 2> /dev/null || true)"

  if [[ -z ${label} ]]; then
    printf '%s\n' '{"running":false,"remain":"","count":"","label":""}'
    return 0
  fi

  REMAIN="$(pomodoro status -f '%!r' 2> /dev/null || true)" \
  COUNT="$(pomodoro status -f '%c' 2> /dev/null || true)" \
  LABEL="${label}" \
    yq -n -o json -I 0 '{
      "running": true,
      "remain": strenv(REMAIN),
      "count": strenv(COUNT),
      "label": strenv(LABEL)
    }'
}

_main "$@"
