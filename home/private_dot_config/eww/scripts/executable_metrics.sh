#!/usr/bin/env bash
# @file metrics.sh
# @brief Stream per-monitor measurements for the widgets
# @description The bar is a share of the monitor and everything inside it is
# measured in `em`, so each monitor needs its own root font size. Carrying that
# as a window argument broke `eww reload`, which recreates a window from the
# arguments it was opened with: a window opened before the argument existed can
# never be reopened. A variable keyed by monitor name has no such problem, and
# it also follows a monitor being plugged in without reopening anything.
set -euo pipefail
# dyshellint disable=BSG099 this drives Hyprland, so it never runs on macOS
shopt -s inherit_errexit

readonly CONFIG="${EWW_CONFIG_DIR:-${HOME}/.config/eww}"
readonly SCRIPTS="${CONFIG}/scripts"
# The share of a monitor's height each scrolling list may take, and the bounds
# it is held between.
readonly CENTRE_SHARE=55
readonly CENTRE_MIN=320
readonly CENTRE_MAX=900
readonly PANEL_SHARE=22
readonly PANEL_MIN=140
readonly PANEL_MAX=420

# The query that folds the measured lines into the map the widgets read.
# dyshellint disable=SC2016 the $ names are yq variables, not shell expansions
readonly PROGRAM='
  strenv(ROWS)
  | split("\n")
  | map(select(. != ""))
  | map(capture("^(?P<name>[^\t]*)\t(?P<width>[^\t]*)\t(?P<height>[^\t]*)\t(?P<centre>[^\t]*)\t(?P<panel>.*)$"))
  | map({
      "key": .name,
      "value": {
        "width": (.width | to_number),
        "height": (.height | to_number),
        "centre_list": (.centre | to_number),
        "panel_list": (.panel | to_number)
      }
    })
  | from_entries
'

# @description Print the measurements of every monitor as one JSON line.
# @description Everything here is in logical pixels, which is what a surface is
# laid out in. The compositor already turns those into physical ones through
# each monitor's scale, so a list that is a share of the logical height comes
# out the right size on a scaled monitor without any help.
#
# eww reads `scroll :height` as pixels only, so the share has to be worked out
# here rather than written as a percentage in the widget.
# @noargs
# @stdout One JSON object keyed by monitor name.
function _emit {
  local rows

  rows="$(
    hyprctl monitors -j 2> /dev/null \
      | yq -p json -o yaml '.[] | [.name, .width, .height, .scale] | join(" ")' 2> /dev/null \
      | awk -v cs="${CENTRE_SHARE}" -v cl="${CENTRE_MIN}" -v ch="${CENTRE_MAX}" \
        -v ps="${PANEL_SHARE}" -v pl="${PANEL_MIN}" -v ph="${PANEL_MAX}" '
        function clamp(value, low, high) {
          if (value < low) return low
          if (value > high) return high
          return value
        }
        {
          scale = ($4 == 0 ? 1 : $4)
          width = int($2 / scale)
          height = int($3 / scale)
          printf "%s\t%d\t%d\t%d\t%d\n", $1, width, height,
            clamp(int(height * cs / 100), cl, ch),
            clamp(int(height * ps / 100), pl, ph)
        }
      ' || true
  )"

  ROWS="${rows}" yq -n -o json -I 0 "${PROGRAM}"
}

# @description Print once, then on every change to the monitor layout.
# @noargs
# @stdout One JSON object per line.
function _main {
  local event

  _emit
  while read -r event; do
    case "${event}" in
      monitoradded* | monitorremoved* | configreloaded*)
        sleep 0.5
        _emit
        ;;
      *) ;;
    esac
  done < <(nc -U "$("${SCRIPTS}/hypr_socket.sh")")
}

_main "$@"
