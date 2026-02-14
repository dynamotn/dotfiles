#!/usr/bin/env bash

if [ $(pomodoro status -f '%L') != "" ]; then
	echo "$(pomodoro status -f '%c') | $(pomodoro status -f '%L')"
else
	echo ""
fi
