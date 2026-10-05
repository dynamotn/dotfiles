#!/usr/bin/env bash
# @file audio.sh
# @brief Stream the audio state for the eww bar and its panel
# @description Print the default sink and source, plus every sink that can be
# selected, as one JSON line, then reprint on every PulseAudio event rather
# than polling on a timer.
set -euo pipefail
# dyshellint disable=BSG099 this drives Hyprland, so it never runs on macOS
shopt -s inherit_errexit

readonly SINK="@DEFAULT_AUDIO_SINK@"
readonly SOURCE="@DEFAULT_AUDIO_SOURCE@"

# The query that folds the collected values into the shape the widgets read.
# dyshellint disable=SC2016 the $ names are yq variables, not shell expansions
readonly PROGRAM='{
  "volume": env(VOLUME),
  "muted": env(MUTED),
  "icon": strenv(ICON),
  "description": strenv(DESCRIPTION),
  "source": {
    "volume": env(MIC_VOLUME),
    "muted": env(MIC_MUTED),
    "icon": strenv(MIC_ICON),
    "description": strenv(MIC_DESCRIPTION)
  },
  "sinks": (
    env(SINKS)
    | map({
        "name": .name,
        "description": .description,
        "default": (.name == strenv(DEFAULT_SINK))
      })
  )
}'

# @description Print the volume of a node as a whole percentage.
# @arg $1 string The wpctl node specifier.
# @stdout The volume, 0 to 100 and beyond.
function _volume_of {
  wpctl get-volume "$1" 2> /dev/null | awk '{ printf "%d", $2 * 100 }'
}

# @description Report whether a node is muted.
# @arg $1 string The wpctl node specifier.
# @stdout `true` or `false`.
function _muted_of {
  if wpctl get-volume "$1" 2> /dev/null | grep -q "\[MUTED\]"; then
    printf '%s\n' "true"
  else
    printf '%s\n' "false"
  fi
}

# @description Print the description of a node, as PipeWire names it.
# @arg $1 string The wpctl node specifier.
# @stdout The description, or nothing.
function _description_of {
  wpctl inspect "$1" 2> /dev/null \
    | sed -n 's/^ *\*\? *node\.description = "\(.*\)"$/\1/p' | head -1
}

# @description Print the speaker icon for a volume and mute state.
# @arg $1 int The volume percentage.
# @arg $2 string `true` when muted.
# @stdout One nerd font glyph.
function _sink_icon {
  local volume="$1" muted="$2"

  if [[ ${muted} == true ]]; then
    printf '%s\n' "󰝟"
  elif ((10#${volume} >= 66)); then
    printf '%s\n' "󰕾"
  elif ((10#${volume} >= 33)); then
    printf '%s\n' "󰖀"
  elif ((10#${volume} > 0)); then
    printf '%s\n' "󰕿"
  else
    printf '%s\n' "󰝟"
  fi
}

# @description Print the microphone icon for a mute state.
# @arg $1 string `true` when muted.
# @stdout One nerd font glyph.
function _source_icon {
  if [[ $1 == true ]]; then
    printf '%s\n' "󰍭"
  else
    printf '%s\n' "󰍬"
  fi
}

# @description Print the whole audio state as a JSON object.
# @noargs
# @stdout One JSON object.
function _emit {
  local volume muted icon description
  local mic_volume mic_muted mic_icon mic_description
  local sinks default_sink

  volume="$(_volume_of "${SINK}")"
  muted="$(_muted_of "${SINK}")"
  icon="$(_sink_icon "${volume:-0}" "${muted}")"
  description="$(_description_of "${SINK}")"

  mic_volume="$(_volume_of "${SOURCE}")"
  mic_muted="$(_muted_of "${SOURCE}")"
  mic_icon="$(_source_icon "${mic_muted}")"
  mic_description="$(_description_of "${SOURCE}")"

  default_sink="$(pactl get-default-sink 2> /dev/null || true)"
  sinks="$(pactl -f json list sinks 2> /dev/null || printf '%s\n' '[]')"

  VOLUME="${volume:-0}" MUTED="${muted}" ICON="${icon}" \
    DESCRIPTION="${description:-Unknown output}" \
    MIC_VOLUME="${mic_volume:-0}" MIC_MUTED="${mic_muted}" MIC_ICON="${mic_icon}" \
    MIC_DESCRIPTION="${mic_description:-Unknown input}" \
    SINKS="${sinks}" DEFAULT_SINK="${default_sink}" \
    yq -n -o json -I 0 "${PROGRAM}"
}

# @description Print the state once, then on every event that can change it.
# @noargs
# @stdout One JSON object per line.
function _main {
  local event

  _emit
  # `pactl subscribe` also reports every stream coming and going, which leaves
  # the sinks untouched, so only reprint on the events that can change them.
  while read -r event; do
    case "${event}" in
      *" on sink"* | *" on source"* | *" on server"*) _emit ;;
      *) ;;
    esac
  done < <(pactl subscribe 2> /dev/null)
}

_main "$@"
