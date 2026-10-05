#!/usr/bin/env bash
# @file mpris.sh
# @brief Stream the currently playing media for the eww bar
# @description Print the status, title, artist and an icon of the most recently
# active MPRIS player as one JSON line, and reprint it whenever playerctl
# reports a change. Print an inactive payload when no player is running, so the
# widget can hide itself.
set -euo pipefail

readonly SEPARATOR=$'\x1f'
# Printed in two pieces to keep the source lines short; it stays one line of
# output, which is what eww reads.
readonly IDLE_HEAD='{"active":false,"status":"Stopped","icon":"󰝛","title":"","artist":"",'
readonly IDLE_TAIL='"album":"","player":"","art":"","shuffle":false,"loop":"None"}'

# The playerctl template, split so no source line runs long.
FORMAT="{{status}}${SEPARATOR}{{title}}${SEPARATOR}{{artist}}${SEPARATOR}{{album}}"
FORMAT+="${SEPARATOR}{{playerName}}${SEPARATOR}{{mpris:artUrl}}"
FORMAT+="${SEPARATOR}{{shuffle}}${SEPARATOR}{{loop}}"
readonly FORMAT

# @description Print the payload that tells the widget to hide itself.
# @noargs
# @stdout One JSON object.
function _idle {
  printf '%s%s\n' "${IDLE_HEAD}" "${IDLE_TAIL}"
}

# @description Turn one playerctl record into the JSON the widget consumes.
# @arg $1 string The record, as status, title, artist and player, unit separated.
# @stdout One JSON object.
function _render {
  local record="$1" status title artist album player art shuffle loop icon

  IFS="${SEPARATOR}" read -r status title artist album player art shuffle loop \
    <<< "${record}"

  if [[ -z ${status} || ${status} == "No players found" ]]; then
    _idle
    return 0
  fi

  case "${status}" in
    Playing) icon="󰏤" ;; # the button pauses, so it carries the pause glyph
    Paused) icon="󰐊" ;;
    *) icon="󰓛" ;;
  esac

  STATUS="${status}" TITLE="${title:-Unknown track}" ARTIST="${artist}" \
    ALBUM="${album}" PLAYER="${player}" ART="${art}" ICON="${icon}" \
    SHUFFLE="${shuffle:-false}" LOOP="${loop:-None}" \
    yq -n -o json -I 0 '{
      "active": true,
      "status": strenv(STATUS),
      "icon": strenv(ICON),
      "title": strenv(TITLE),
      "artist": strenv(ARTIST),
      "album": strenv(ALBUM),
      "player": strenv(PLAYER),
      "art": strenv(ART),
      "shuffle": (strenv(SHUFFLE) == "true"),
      "loop": strenv(LOOP)
    }'
}

# @description Follow playerctl, restarting it whenever the last player exits.
# @noargs
# @stdout One JSON object per line.
function _main {
  local record

  _idle
  # `playerctl --follow` exits once the last player goes away, so restart it
  # and fall back to the inactive payload in between.
  while true; do
    while read -r record; do
      _render "${record}"
    done < <(
      playerctl --follow metadata \
        --format "${FORMAT}" \
        2> /dev/null
    )
    _idle
    sleep 2
  done
}

_main "$@"
