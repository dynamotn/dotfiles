#!/usr/bin/env bash
# @file workspaces.sh
# @brief Show each aerospace workspace on the bar of the monitor that owns it
# @description Run by the hidden `workspaces` item. Adds an item for every
# workspace aerospace has, removes the item of a workspace it dropped, puts
# each item on the display of its monitor and highlights the visible ones, so
# every screen shows only its own workspaces, as Hyprland does.
set -euo pipefail
# readarray, associative arrays and inherit_errexit need bash 4.4; macOS ships 3.2
if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
  printf 'bash 4.4 or later is needed, found %s\n' "${BASH_VERSION}" >&2
  exit 1
fi
shopt -s inherit_errexit

# sketchybar exports these to every item script it runs.
config_dir=${CONFIG_DIR:-${HOME}/.config/sketchybar}

theme_file="${config_dir}/themes/catppuccin.sh"
[[ -r "${theme_file}" ]] || exit 1
# The theme is a chezmoi template, so there is no file to follow here.
# shellcheck source=/dev/null
. "${theme_file}"
focused_label=${SKETCHY_MAUVE:?}
focused_background=${SKETCHY_SURFACE_2:?}
idle_label=${SKETCHY_SUBTEXT_0:?}
idle_background=${SKETCHY_SURFACE_0:?}

#######################################
# @description Map a workspace id to its icon, in the order of
# home/.chezmoitemplates/wm/rules.yaml.tmpl: 1 to 9, then 0
# @arg $1 string Workspace id
# @stdout Icon of the workspace, a generic one for any other id
#######################################
function _get_icon {
  case "$1" in
{{- $rules := includeTemplate "wm/rules.yaml.tmpl" . | fromYaml }}
{{- range $index, $workspace := $rules.workspaces }}
    {{ mod (add $index 1) 10 }}) printf "%s" "{{ $workspace.icon }}" ;; # {{ $workspace.name }}
{{- end }}
    *) printf "" ;;
  esac
}

#######################################
# @description List the workspaces as "id|display|visible", ordered like the
# keyboard row: 1 to 9, 0, then any workspace aerospace created on its own
# @noargs
# @stdout One workspace per line
#######################################
function _list_workspaces {
  local listing
  listing=$(aerospace list-workspaces --all \
    --format '%{workspace}|%{monitor-appkit-nsscreen-screens-id}|%{workspace-is-visible}')
  awk -F'|' '{
      key = ($1 !~ /^[0-9]+$/) ? 1000000 : ($1 == "0") ? 9.5 : $1
      print key "|" $0
    }' <<< "${listing}" \
    | sort -t'|' -k1,1g \
    | cut -d'|' -f2-
}

#######################################
# @description Bring the workspace items in line with aerospace in one
# sketchybar call
# @noargs
#######################################
function _main {
  local focused=${FOCUSED_WORKSPACE:-}
  if [[ -z "${focused}" ]]; then
    focused=$(aerospace list-workspaces --focused)
  fi

  local -A stale=()
  local -a workspace_items=() workspaces=() args=()
  local bar workspace_item workspace id display visible listing
  bar=$(sketchybar --query bar)
  listing=$(jq -r '.items[] | select(startswith("workspace."))' <<< "${bar}")
  [[ -z "${listing}" ]] || readarray -t workspace_items <<< "${listing}"
  for workspace_item in "${workspace_items[@]}"; do
    stale["${workspace_item}"]=1
  done

  listing=$(_list_workspaces)
  [[ -z "${listing}" ]] || readarray -t workspaces <<< "${listing}"
  for workspace in "${workspaces[@]}"; do
    IFS='|' read -r id display visible <<< "${workspace}"
    workspace_item="workspace.${id}"
    if [[ -z "${stale["${workspace_item}"]:-}" ]]; then
      args+=(--add item "${workspace_item}" left)
      args+=(--set "${workspace_item}"
        background.corner_radius=5
        background.height=20
        label="$(_get_icon "${id}") "
        click_script="aerospace workspace ${id}")
    fi
    stale["${workspace_item}"]=""

    args+=(--set "${workspace_item}" display="${display}")
    if [[ "${id}" == "${focused}" ]]; then
      args+=(label.color="${focused_label}" background.drawing=on background.color="${focused_background}")
    elif [[ "${visible}" == "true" ]]; then
      args+=(label.color="${focused_label}" background.drawing=off background.color="${idle_background}")
    else
      args+=(label.color="${idle_label}" background.drawing=off background.color="${idle_background}")
    fi
  done

  for workspace_item in "${!stale[@]}"; do
    if [[ -n "${stale["${workspace_item}"]}" ]]; then
      args+=(--remove "${workspace_item}")
    fi
  done

  if ((${#args[@]} > 0)); then
    sketchybar "${args[@]}"
  fi
}

_main "$@"
