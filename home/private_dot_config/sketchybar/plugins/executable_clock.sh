#!/usr/bin/env bash
# @file clock.sh
# @brief Show the date and the time on the clock items
# @description Run by the `clock.time` item every 30 seconds and on wake.
set -euo pipefail

day=$(date '+%a %d %b')
time=$(date '+%H:%M')
sketchybar --set clock.date label="${day}" --set clock.time label="${time}"
