#!/usr/bin/env bash
# @file mpris.sh
# @brief Stream the currently playing media for the eww bar
# @description Print the status, title, artist and an icon of the most recently
# active MPRIS player as one JSON line, and reprint it whenever playerctl
# reports a change. Print an inactive payload when no player is running, so the
# widget can hide itself.
set -euo pipefail

readonly SEPARATOR=$'\x1f'
readonly IDLE='{"active":false,"status":"Stopped","icon":"󰝛","title":"","artist":"","player":""}'

# @description Turn one playerctl record into the JSON the widget consumes.
# @arg $1 string The record, as status, title, artist and player, unit separated.
# @stdout One JSON object.
function _render {
  local record="$1" status title artist player icon

  IFS="${SEPARATOR}" read -r status title artist player <<< "${record}"

  if [[ -z ${status} || ${status} == "No players found" ]]; then
    printf '%s\n' "${IDLE}"
    return 0
  fi

  case "${status}" in
    Playing) icon="󰏤" ;; # the button pauses, so it carries the pause glyph
    Paused) icon="󰐊" ;;
    *) icon="󰓛" ;;
  esac

  jq -nc \
    --arg status "${status}" \
    --arg title "${title:-Unknown track}" \
    --arg artist "${artist}" \
    --arg player "${player}" \
    --arg icon "${icon}" \
    '{active: true, status: $status, icon: $icon, title: $title,
      artist: $artist, player: $player}'
}

# @description Follow playerctl, restarting it whenever the last player exits.
# @noargs
# @stdout One JSON object per line.
function _main {
  local record

  printf '%s\n' "${IDLE}"
  # `playerctl --follow` exits once the last player goes away, so restart it
  # and fall back to the inactive payload in between.
  while true; do
    while read -r record; do
      _render "${record}"
    done < <(
      playerctl --follow metadata \
        --format "{{status}}${SEPARATOR}{{title}}${SEPARATOR}{{artist}}${SEPARATOR}{{playerName}}" \
        2> /dev/null
    )
    printf '%s\n' "${IDLE}"
    sleep 2
  done
}

_main "$@"
