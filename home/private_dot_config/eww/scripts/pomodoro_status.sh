#!/usr/bin/env bash
# @file pomodoro_status.sh
# @brief Render the current pomodoro state for the eww bar
# @description Render the current pomodoro state for the eww bar, as the
# cycle count and the remaining label, or an empty string when no pomodoro is
# running.

if [[ -n "$(pomodoro status -f '%L')" ]]; then
  echo "$(pomodoro status -f '%c') | $(pomodoro status -f '%L')"
else
  echo ""
fi
