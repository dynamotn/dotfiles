#!/usr/bin/env bash
# @file audio.sh
# @brief Stream the default sink state for the eww bar
# @description Print the volume, the mute flag, an icon and the description of
# the default PipeWire sink as one JSON line, then reprint it on every
# PulseAudio event rather than polling on a timer.
set -euo pipefail

readonly SINK="@DEFAULT_AUDIO_SINK@"

# @description Print the current sink state as a JSON object.
# @noargs
# @stdout One JSON object.
function _emit {
  local raw volume muted icon description

  raw="$(wpctl get-volume "${SINK}" 2> /dev/null || printf '%s\n' "Volume: 0.00")"
  volume="$(awk '{ printf "%d", $2 * 100 }' <<< "${raw}")"
  if [[ ${raw} == *"[MUTED]"* ]]; then
    muted=true
  else
    muted=false
  fi

  if [[ ${muted} == true ]]; then
    icon="󰝟"
  elif ((volume >= 66)); then
    icon="󰕾"
  elif ((volume >= 33)); then
    icon="󰖀"
  elif ((volume > 0)); then
    icon="󰕿"
  else
    icon="󰝟"
  fi

  description="$(
    wpctl inspect "${SINK}" 2> /dev/null \
      | sed -n 's/^ *\*\? *node\.description = "\(.*\)"$/\1/p' | head -1
  )"

  VOLUME="${volume}" MUTED="${muted}" ICON="${icon}" \
    DESCRIPTION="${description:-Unknown output}" \
    yq -n -o json -I 0 '{
      "volume": env(VOLUME),
      "muted": env(MUTED),
      "icon": strenv(ICON),
      "description": strenv(DESCRIPTION)
    }'
}

# @description Print the sink state once, then on every event that can change it.
# @noargs
# @stdout One JSON object per line.
function _main {
  local event

  _emit
  # `pactl subscribe` also reports every stream coming and going, which leaves
  # the sink untouched, so only reprint on the events that can change it.
  while read -r event; do
    case "${event}" in
      *" on sink "* | *" on server"*) _emit ;;
      *) ;;
    esac
  done < <(pactl subscribe 2> /dev/null)
}

_main "$@"
