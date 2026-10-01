#!/usr/bin/env bash
# shellcheck disable=2154
# @file dytoy_tui.sh
# @brief Library `dytoy_tui` to pick and install dytoy tools in a full-screen interface
# @description Library `dytoy_tui` drives `dytoy` from a full-screen interface
# built on the `screen` module of dybatpho. It has two phases:
#
# - **pick**: one tab per installer method, a list of tools with a checkbox and
#   whether each is already installed, and the YAML of the tool under the
#   cursor.
# - **install**: the picked tools run one at a time, each in its own `dytoy
#   <method> -t <tool>` child whose output goes to a log file. The screen shows
#   a gauge, the state of every tool, and the tail of the log being followed.
#
# Each tool runs as a child rather than in this shell so that a failing tool,
# which ends its process with `dybatpho::die`, does not end the interface, and
# so that its output can be shown in a pane instead of scrolling over the
# frame. A child cannot answer a prompt, so `sudo` is authenticated before the
# install phase and every child sees a `sudo` that never asks.
dybatpho::load screen

# Every enabled tool, in install order, as parallel arrays indexed alike.
declare -ga DYTOY_TUI_NAME=()
declare -ga DYTOY_TUI_METHOD=()
declare -ga DYTOY_TUI_ESSENTIAL=()
# `yes`, `no`, or `unknown` (a package manager tool, too slow to ask about).
declare -ga DYTOY_TUI_INSTALLED=()
declare -ga DYTOY_TUI_PICKED=()
# `pending`, `running`, `ok`, `failed`, or `skipped`.
declare -ga DYTOY_TUI_STATE=()
declare -ga DYTOY_TUI_LOG=()
declare -ga DYTOY_TUI_STARTED=()
declare -ga DYTOY_TUI_ELAPSED=()
# The YAML of each tool by index, read on first view.
declare -gA DYTOY_TUI_DETAIL=()
# The cursor of each pick tab, by method.
declare -gA DYTOY_TUI_CURSOR=()

# Indexes of the picked tools, in the order they install.
declare -ga DYTOY_TUI_QUEUE=()
DYTOY_TUI_QUEUE_POS=0
DYTOY_TUI_PID=""
DYTOY_TUI_CURRENT=-1
# The tool whose log is shown, as a position in the queue.
DYTOY_TUI_VIEW=0
DYTOY_TUI_FOLLOW=true

# `pick`, `install`, or `done`.
DYTOY_TUI_PHASE="pick"
# `normal` or `confirm`, the latter while the stop dialog is up.
DYTOY_TUI_MODE="normal"
DYTOY_TUI_TAB=0
DYTOY_TUI_RUNNING=true
DYTOY_TUI_STATUS=""
DYTOY_TUI_SELF=""
DYTOY_TUI_LOG_DIR=""
DYTOY_TUI_WRAP_DIR=""
DYTOY_TUI_KEEPALIVE_PID=""

declare -ga DYTOY_TUI_SPINNER=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
# `true` once a picked tool failed or was stopped, read by the caller.
# shellcheck disable=SC2034
DYTOY_TUI_FAILED=false

#######################################
# @description Return success when there is a terminal to take over. Both ends
# matter: keys come from stdin and the frame goes to the terminal, and a run
# with either redirected (a chezmoi hook, a pipe, a test) is not interactive.
# @noargs
#######################################
function dytoy_tui::has_terminal {
  [[ -t 0 && -t 1 && -e /dev/tty ]]
}

#######################################
# @description Read every enabled tool from the YAML file, in the order the
# methods run. Nothing starts picked: what to install is the user's choice.
# @noargs
# @env DYTOY_METHODS array Installer methods, in the order they run
# @env ONLY_ESSENTIAL boolean Only list essential tools
# @set DYTOY_TUI_NAME, DYTOY_TUI_METHOD, DYTOY_TUI_ESSENTIAL, DYTOY_TUI_INSTALLED, DYTOY_TUI_PICKED
#######################################
function dytoy_tui::load_tools {
  DYTOY_TUI_NAME=()
  DYTOY_TUI_METHOD=()
  DYTOY_TUI_ESSENTIAL=()
  DYTOY_TUI_INSTALLED=()
  DYTOY_TUI_PICKED=()
  DYTOY_TUI_STATE=()
  DYTOY_TUI_LOG=()
  DYTOY_TUI_STARTED=()
  DYTOY_TUI_ELAPSED=()
  DYTOY_TUI_DETAIL=()

  # One query for the whole file rather than one per tool: the list is read
  # before the first frame, and a `yq` call per tool is seconds of blank screen.
  local rows
  rows=$(dybatpho::yaml_query "$(dytoy::yaml_file)" \
    'explode(.) | .[] | select(.enabled != false and .enabled != "false")
      | [.name, .method, (.is_essential // false)] | @tsv' -r)

  local method name tool_method essential installed
  for method in "${DYTOY_METHODS[@]}"; do
    while IFS=$'\t' read -r name tool_method essential; do
      [[ -n "${name}" && "${tool_method}" == "${method}" ]] || continue
      if dybatpho::is true "${ONLY_ESSENTIAL}" && ! dybatpho::is true "${essential}"; then
        continue
      fi
      installed="$(dytoy_tui::detect_installed "${name}" "${method}")"
      DYTOY_TUI_NAME+=("${name}")
      DYTOY_TUI_METHOD+=("${method}")
      DYTOY_TUI_ESSENTIAL+=("${essential}")
      DYTOY_TUI_INSTALLED+=("${installed}")
      DYTOY_TUI_PICKED+=(false)
      DYTOY_TUI_STATE+=("pending")
      DYTOY_TUI_LOG+=("")
      DYTOY_TUI_STARTED+=(0)
      DYTOY_TUI_ELAPSED+=(0)
    done <<< "${rows}"
    DYTOY_TUI_CURSOR["${method}"]=0
  done
}

#######################################
# @description Print whether a tool is installed, the same way the installers
# decide to skip it: a command on `PATH` or a file in `~/.local/bin`.
# @arg $1 string Name of tool
# @arg $2 string Method of tool
# @stdout `yes`, `no`, or `unknown` for a package manager tool
#######################################
function dytoy_tui::detect_installed {
  local name method
  dybatpho::expect_args name method -- "$@"
  if [[ "${method}" == "os" ]]; then
    echo "unknown"
  elif dybatpho::is command "${name}" \
    || dybatpho::is file "$(dybatpho::path_join "${HOME}" ".local" "bin" "${name}")"; then
    echo "yes"
  else
    echo "no"
  fi
}

#######################################
# @description Fill an array with the indexes of the tools of one method.
# @arg $1 string Name of the array variable receiving the indexes
# @arg $2 string Method
#######################################
function dytoy_tui::tab_items {
  local -n __dytoy_tui_items="$1"
  local method="$2" index
  __dytoy_tui_items=()
  for index in "${!DYTOY_TUI_NAME[@]}"; do
    [[ "${DYTOY_TUI_METHOD[index]}" == "${method}" ]] && __dytoy_tui_items+=("${index}")
  done
  return 0
}

#######################################
# @description Print how many tools are picked, overall or for one method.
# @arg $1 string Optional method
# @stdout The count
#######################################
function dytoy_tui::picked_count {
  local method="${1-}" index count=0
  for index in "${!DYTOY_TUI_NAME[@]}"; do
    [[ -z "${method}" || "${DYTOY_TUI_METHOD[index]}" == "${method}" ]] || continue
    dybatpho::is true "${DYTOY_TUI_PICKED[index]}" && count=$((count + 1))
  done
  echo "${count}"
}

#######################################
# @description Fill an array with the arguments of the `dytoy` child that
# installs one tool, passing the options this run was given down to it.
# @arg $1 string Name of the array variable receiving the arguments
# @arg $2 number Index of the tool
# @arg $3 boolean Whether to sync the package repositories in this child
# @env LOG_LEVEL, DRY_RUN, ONLY_ESSENTIAL, ONLY_NOT_INSTALLED, LIST_CONTENTS
#######################################
function dytoy_tui::child_args {
  local -n __dytoy_tui_args="$1"
  local index="$2" sync="$3"
  __dytoy_tui_args=(
    "${DYTOY_TUI_METHOD[index]}" --tool "${DYTOY_TUI_NAME[index]}" --log-level "${LOG_LEVEL}"
  )
  dybatpho::is true "${DRY_RUN}" && __dytoy_tui_args+=(--dry-run)
  dybatpho::is true "${ONLY_ESSENTIAL}" && __dytoy_tui_args+=(--essential)
  if dybatpho::is true "${ONLY_NOT_INSTALLED}"; then
    __dytoy_tui_args+=(--check-installed)
  else
    __dytoy_tui_args+=(--no-check-installed)
  fi
  dybatpho::is true "${sync}" && __dytoy_tui_args+=(--sync)
  dybatpho::is true "${LIST_CONTENTS}" && __dytoy_tui_args+=(--list)
  return 0
}

#######################################
# @description Fill an array with the last lines of a log, cleaned up for the
# screen: colours and other escape sequences dropped, a line redrawn with `\r`
# reduced to what it ended as, and tabs expanded.
# @arg $1 string Name of the array variable receiving the lines
# @arg $2 string Log file
# @arg $3 number Number of lines
#######################################
function dytoy_tui::log_tail {
  local -n __dytoy_tui_lines="$1"
  local file="$2" count="$3"
  __dytoy_tui_lines=()
  [[ -f "${file}" ]] && ((count > 0)) || return 0
  readarray -t __dytoy_tui_lines < <(
    tail -n "${count}" "${file}" | LC_ALL=C sed -E \
      -e 's/\x1B\[[0-9;?]*[A-Za-z]//g' \
      -e 's/\x1B\][^\x07]*\x07//g' \
      -e 's/\r$//' -e 's/.*\r//' \
      -e 's/\t/  /g' \
      -e 's/[\x01-\x08\x0B-\x1F\x7F]//g'
  )
}

#######################################
# @description Fill the queue with the picked tools, in install order, and
# reset their state.
# @noargs
#######################################
function dytoy_tui::build_queue {
  DYTOY_TUI_QUEUE=()
  local index
  for index in "${!DYTOY_TUI_NAME[@]}"; do
    dybatpho::is true "${DYTOY_TUI_PICKED[index]}" || continue
    DYTOY_TUI_QUEUE+=("${index}")
    DYTOY_TUI_STATE[index]="pending"
  done
  DYTOY_TUI_QUEUE_POS=0
  DYTOY_TUI_VIEW=0
  DYTOY_TUI_FOLLOW=true
  DYTOY_TUI_CURRENT=-1
}

#######################################
# @description Print how many queued tools ended in a state.
# @arg $1 string State
# @stdout The count
#######################################
function dytoy_tui::count_state {
  local state="$1" index count=0
  for index in "${DYTOY_TUI_QUEUE[@]}"; do
    [[ "${DYTOY_TUI_STATE[index]}" == "${state}" ]] && count=$((count + 1))
  done
  echo "${count}"
}

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

#######################################
# @description Draw one row of text across a rectangle, padded to its width so
# a style covers the whole row.
# @arg $1 string Rectangle to draw in, only its first row is used
# @arg $2 string Text
# @arg $3 string SGR parameters
#######################################
function dytoy_tui::draw_bar {
  local x y width text="$2" style="$3" used
  read -r x y width _ <<< "$1"
  dybatpho::screen_width used "${text}"
  ((used < width)) && printf -v text '%s%*s' "${text}" "$((width - used))" ""
  dybatpho::screen_put "${y}" "${x}" "${text}" "${style}"
}

#######################################
# @description Read the YAML of a tool, once, and remember it.
# @arg $1 number Index of the tool
# @set DYTOY_TUI_DETAIL The YAML of the tool
#######################################
function dytoy_tui::load_detail {
  local index="$1"
  [[ -n "${DYTOY_TUI_DETAIL[${index}]+set}" ]] && return 0
  DYTOY_TUI_DETAIL["${index}"]="$(dybatpho::yaml_query "$(dytoy::yaml_file)" \
    "explode(.) | .[] | select(.name == \"${DYTOY_TUI_NAME[index]}\" and .method == \"${DYTOY_TUI_METHOD[index]}\")" \
    2> /dev/null)" || DYTOY_TUI_DETAIL["${index}"]=""
}

#######################################
# @description Draw the pick phase into the buffer.
# @noargs
#######################################
function dytoy_tui::draw_pick {
  local -a frame=() body=() tabs=() items=() lines=()
  dybatpho::screen_layout frame vertical "${DYBATPHO_SCREEN_RECT}" length:1 fill:1 length:1

  local method
  for method in "${DYTOY_METHODS[@]}"; do
    dytoy_tui::tab_items items "${method}"
    tabs+=("${method} $(dytoy_tui::picked_count "${method}")/${#items[@]}")
  done
  dybatpho::screen_tabs "${frame[0]}" tabs active:"${DYTOY_TUI_TAB}"

  method="${DYTOY_METHODS[DYTOY_TUI_TAB]}"
  dytoy_tui::tab_items items "${method}"
  local cursor="${DYTOY_TUI_CURSOR[${method}]:-0}"

  dybatpho::screen_layout body horizontal "${frame[1]}" percent:40 fill:1
  dybatpho::screen_block "${body[0]}" title:"Tools" border:rounded
  local list_rect="${DYBATPHO_SCREEN_INNER}"
  if ((${#items[@]} == 0)); then
    dybatpho::screen_text "${list_rect}" "No ${method} tool to install" align:center style:"2"
  else
    local index box mark
    for index in "${items[@]}"; do
      box="[ ]"
      dybatpho::is true "${DYTOY_TUI_PICKED[index]}" && box="[x]"
      case "${DYTOY_TUI_INSTALLED[index]}" in
        yes) mark="✓" ;;
        no) mark="·" ;;
        *) mark="?" ;;
      esac
      local line="${box} ${mark} ${DYTOY_TUI_NAME[index]}"
      dybatpho::is true "${DYTOY_TUI_ESSENTIAL[index]}" && line+=" ★"
      lines+=("${line}")
    done
    dybatpho::screen_list "${list_rect}" lines selected:"${cursor}"
  fi

  local title="Details"
  if ((${#items[@]} > 0)); then
    local selected="${items[cursor]}"
    title="${DYTOY_TUI_NAME[selected]}"
    dybatpho::screen_block "${body[1]}" title:"${title}" border:rounded
    local detail_rect="${DYBATPHO_SCREEN_INNER}"
    dytoy_tui::load_detail "${selected}"
    dybatpho::screen_text "${detail_rect}" "${DYTOY_TUI_DETAIL[${selected}]}" wrap:false
  else
    dybatpho::screen_block "${body[1]}" title:"${title}" border:rounded
  fi

  local status=" ${DYTOY_TUI_STATUS}"
  if [[ -z "${DYTOY_TUI_STATUS}" ]]; then
    status=" $(dytoy_tui::picked_count) picked   space pick  a all  ←→ tab  enter install  q quit"
    status+="   ✓ installed  · missing  ★ essential"
  fi
  dytoy_tui::draw_bar "${frame[2]}" "${status}" "7"
}

#######################################
# @description Set a variable to the marker of a queued tool's state. It is
# drawn once per tool per frame, so it writes to a variable rather than paying
# for a subshell each time.
# @arg $1 string Name of the variable receiving the marker
# @arg $2 number Index of the tool
#######################################
function dytoy_tui::state_mark_into {
  local -n __dytoy_tui_mark="$1"
  local index="$2"
  case "${DYTOY_TUI_STATE[index]}" in
    ok) __dytoy_tui_mark="✓" ;;
    failed) __dytoy_tui_mark="✗" ;;
    skipped) __dytoy_tui_mark="-" ;;
    running)
      local tick="${EPOCHREALTIME/[.,]/}"
      __dytoy_tui_mark="${DYTOY_TUI_SPINNER[(tick / 100000) % ${#DYTOY_TUI_SPINNER[@]}]}"
      ;;
    *) __dytoy_tui_mark="·" ;;
  esac
}

#######################################
# @description Draw the install phase into the buffer.
# @noargs
#######################################
function dytoy_tui::draw_install {
  local -a frame=() body=() lines=() tail_lines=()
  dybatpho::screen_layout frame vertical "${DYBATPHO_SCREEN_RECT}" length:3 fill:1 length:1

  local total="${#DYTOY_TUI_QUEUE[@]}" ok failed skipped finished
  ok="$(dytoy_tui::count_state ok)"
  failed="$(dytoy_tui::count_state failed)"
  skipped="$(dytoy_tui::count_state skipped)"
  finished=$((ok + failed + skipped))

  local title="Installing" label style="1;32"
  if [[ "${DYTOY_TUI_PHASE}" == "done" ]]; then
    title="Finished"
    label="${ok} installed, ${failed} failed, ${skipped} skipped"
  else
    label="${finished}/${total}"
    ((DYTOY_TUI_CURRENT >= 0)) && label+="  ${DYTOY_TUI_NAME[DYTOY_TUI_CURRENT]}"
  fi
  ((failed > 0)) && style="1;31"
  dybatpho::is true "${DRY_RUN}" && title+=" (dry run)"
  dybatpho::screen_block "${frame[0]}" title:"${title}" border:rounded
  dybatpho::screen_gauge "${DYBATPHO_SCREEN_INNER}" "${finished}" "$((total > 0 ? total : 1))" \
    label:"${label}" style:"${style}"

  dybatpho::screen_layout body horizontal "${frame[1]}" percent:30 fill:1
  dybatpho::screen_block "${body[0]}" title:"Tools" border:rounded
  local list_rect="${DYBATPHO_SCREEN_INNER}" index elapsed line mark
  for index in "${DYTOY_TUI_QUEUE[@]}"; do
    dytoy_tui::state_mark_into mark "${index}"
    line="${mark} ${DYTOY_TUI_METHOD[index]}/${DYTOY_TUI_NAME[index]}"
    elapsed="${DYTOY_TUI_ELAPSED[index]}"
    [[ "${DYTOY_TUI_STATE[index]}" == "running" ]] \
      && elapsed=$((EPOCHSECONDS - DYTOY_TUI_STARTED[index]))
    [[ "${DYTOY_TUI_STATE[index]}" == "pending" || "${DYTOY_TUI_STATE[index]}" == "skipped" ]] \
      || line+=" (${elapsed}s)"
    lines+=("${line}")
  done
  dybatpho::screen_list "${list_rect}" lines selected:"${DYTOY_TUI_VIEW}" pointer:false

  local viewed="${DYTOY_TUI_QUEUE[DYTOY_TUI_VIEW]:--1}" log_title="Log"
  ((viewed >= 0)) && log_title="Log: ${DYTOY_TUI_NAME[viewed]}"
  dybatpho::is true "${DYTOY_TUI_FOLLOW}" && log_title+=" (following)"
  dybatpho::screen_block "${body[1]}" title:"${log_title}" border:rounded
  local log_rect="${DYBATPHO_SCREEN_INNER}" height
  read -r _ _ _ height <<< "${log_rect}"
  if ((viewed >= 0)) && [[ -n "${DYTOY_TUI_LOG[viewed]}" ]]; then
    dytoy_tui::log_tail tail_lines "${DYTOY_TUI_LOG[viewed]}" "${height}"
    local text=""
    ((${#tail_lines[@]} > 0)) && printf -v text '%s\n' "${tail_lines[@]}"
    dybatpho::screen_text "${log_rect}" "${text%$'\n'}" wrap:false
  else
    dybatpho::screen_text "${log_rect}" "Waiting to start" align:center style:"2"
  fi

  local status
  if [[ "${DYTOY_TUI_PHASE}" == "done" ]]; then
    status=" ↑↓ view log   q quit   logs in ${DYTOY_TUI_LOG_DIR}"
  else
    status=" ↑↓ view log   f follow   q stop"
  fi
  dytoy_tui::draw_bar "${frame[2]}" "${status}" "7"

  if [[ "${DYTOY_TUI_MODE}" == "confirm" ]]; then
    local box
    dybatpho::screen_rect_center box "${DYBATPHO_SCREEN_RECT}" 44 7
    dybatpho::screen_popup "${box}" title:"Stop installing" border:double
    dybatpho::screen_text "${DYBATPHO_SCREEN_INNER}" \
      $'Stop the running tool and skip the rest?\n\ny = stop    n = keep going' align:center
  fi
}

#######################################
# @description Draw the current phase into the buffer.
# @noargs
#######################################
function dytoy_tui::draw {
  dybatpho::screen_clear
  if [[ "${DYTOY_TUI_PHASE}" == "pick" ]]; then
    dytoy_tui::draw_pick
  else
    dytoy_tui::draw_install
  fi
}

# ---------------------------------------------------------------------------
# Keys
# ---------------------------------------------------------------------------

#######################################
# @description Act on one key in the pick phase.
# @arg $1 string Event name
#######################################
function dytoy_tui::handle_pick_key {
  local -a items=()
  local method="${DYTOY_METHODS[DYTOY_TUI_TAB]}" tab_count="${#DYTOY_METHODS[@]}"
  dytoy_tui::tab_items items "${method}"
  local count="${#items[@]}" cursor="${DYTOY_TUI_CURSOR[${method}]:-0}"
  DYTOY_TUI_STATUS=""

  case "$1" in
    char:q | escape | eof) DYTOY_TUI_RUNNING=false ;;
    up | char:k) ((count > 0)) && cursor=$(((cursor - 1 + count) % count)) ;;
    down | char:j) ((count > 0)) && cursor=$(((cursor + 1) % count)) ;;
    home | char:g) cursor=0 ;;
    end | char:G) ((count > 0)) && cursor=$((count - 1)) ;;
    left | char:h) DYTOY_TUI_TAB=$(((DYTOY_TUI_TAB - 1 + tab_count) % tab_count)) ;;
    right | char:l | tab) DYTOY_TUI_TAB=$(((DYTOY_TUI_TAB + 1) % tab_count)) ;;
    space)
      if ((count > 0)); then
        local index="${items[cursor]}"
        if dybatpho::is true "${DYTOY_TUI_PICKED[index]}"; then
          DYTOY_TUI_PICKED[index]=false
        else
          DYTOY_TUI_PICKED[index]=true
        fi
        cursor=$(((cursor + 1) % count))
      fi
      ;;
    char:a)
      # Pick the whole tab, or clear it when it is already fully picked.
      local index value=false
      (($(dytoy_tui::picked_count "${method}") < count)) && value=true
      for index in "${items[@]}"; do
        DYTOY_TUI_PICKED[index]="${value}"
      done
      ;;
    enter)
      if (($(dytoy_tui::picked_count) == 0)); then
        DYTOY_TUI_STATUS="Nothing picked: press space to pick a tool"
      else
        DYTOY_TUI_PHASE="install"
      fi
      ;;
    resize) dybatpho::screen_size || true ;;
    *) ;;
  esac
  DYTOY_TUI_CURSOR["${method}"]="${cursor}"
  return 0
}

#######################################
# @description Act on one key in the install phase.
# @arg $1 string Event name
#######################################
function dytoy_tui::handle_install_key {
  local count="${#DYTOY_TUI_QUEUE[@]}"
  if [[ "${DYTOY_TUI_MODE}" == "confirm" ]]; then
    # Only an explicit `y` stops anything: a dialog a stray key confirms reads
    # as a safeguard without being one.
    case "$1" in
      char:y | char:Y)
        dytoy_tui::stop
        DYTOY_TUI_MODE="normal"
        ;;
      resize) dybatpho::screen_size || true ;;
      *) DYTOY_TUI_MODE="normal" ;;
    esac
    return 0
  fi

  case "$1" in
    char:q | escape | eof)
      if [[ "${DYTOY_TUI_PHASE}" == "done" ]]; then
        DYTOY_TUI_RUNNING=false
      elif [[ "$1" == "eof" ]]; then
        dytoy_tui::stop
        DYTOY_TUI_RUNNING=false
      else
        DYTOY_TUI_MODE="confirm"
      fi
      ;;
    enter) [[ "${DYTOY_TUI_PHASE}" == "done" ]] && DYTOY_TUI_RUNNING=false ;;
    up | char:k)
      DYTOY_TUI_FOLLOW=false
      ((DYTOY_TUI_VIEW > 0)) && DYTOY_TUI_VIEW=$((DYTOY_TUI_VIEW - 1))
      ;;
    down | char:j)
      DYTOY_TUI_FOLLOW=false
      ((DYTOY_TUI_VIEW < count - 1)) && DYTOY_TUI_VIEW=$((DYTOY_TUI_VIEW + 1))
      ;;
    char:f)
      DYTOY_TUI_FOLLOW=true
      dytoy_tui::follow
      ;;
    resize) dybatpho::screen_size || true ;;
    *) ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# Running
# ---------------------------------------------------------------------------

#######################################
# @description Point the log view at the running tool, or at the last one to
# finish, while following.
# @noargs
#######################################
function dytoy_tui::follow {
  dybatpho::is true "${DYTOY_TUI_FOLLOW}" || return 0
  local position=$((DYTOY_TUI_QUEUE_POS - 1))
  ((position >= 0)) || position=0
  DYTOY_TUI_VIEW="${position}"
}

#######################################
# @description Start the next queued tool, or end the install phase when none
# is left.
# @noargs
#######################################
function dytoy_tui::start_next {
  if ((DYTOY_TUI_QUEUE_POS >= ${#DYTOY_TUI_QUEUE[@]})); then
    DYTOY_TUI_PHASE="done"
    DYTOY_TUI_CURRENT=-1
    return 0
  fi
  local index="${DYTOY_TUI_QUEUE[DYTOY_TUI_QUEUE_POS]}"
  DYTOY_TUI_QUEUE_POS=$((DYTOY_TUI_QUEUE_POS + 1))
  DYTOY_TUI_CURRENT="${index}"

  # The repositories are synced once, by the first package manager tool,
  # rather than once per tool.
  local sync=false position
  if dybatpho::is true "${SYNC_REPO}" && [[ "${DYTOY_TUI_METHOD[index]}" == "os" ]]; then
    sync=true
    for ((position = 0; position < DYTOY_TUI_QUEUE_POS - 1; position++)); do
      [[ "${DYTOY_TUI_METHOD[${DYTOY_TUI_QUEUE[position]}]}" == "os" ]] && sync=false
    done
  fi

  local -a args=()
  dytoy_tui::child_args args "${index}" "${sync}"
  local log="${DYTOY_TUI_LOG_DIR}/${DYTOY_TUI_METHOD[index]}-${DYTOY_TUI_NAME[index]}.log"
  DYTOY_TUI_LOG[index]="${log}"
  DYTOY_TUI_STATE[index]="running"
  DYTOY_TUI_STARTED[index]="${EPOCHSECONDS}"
  printf '$ dytoy %s\n' "${args[*]}" > "${log}"

  # Job control gives the child a process group of its own, so stopping it
  # reaches whatever it started too. Its stdin is closed so nothing waits on a
  # prompt nobody can see.
  local path="${PATH}"
  [[ -n "${DYTOY_TUI_WRAP_DIR}" ]] && path="${DYTOY_TUI_WRAP_DIR}:${PATH}"
  set -m
  PATH="${path}" NO_COLOR=1 "${DYTOY_TUI_SELF}" "${args[@]}" >> "${log}" 2>&1 < /dev/null &
  DYTOY_TUI_PID=$!
  set +m
  dytoy_tui::follow
}

#######################################
# @description Collect the running tool once it has ended, and start the next.
# @noargs
#######################################
function dytoy_tui::poll {
  [[ "${DYTOY_TUI_PHASE}" == "install" ]] || return 0
  if [[ -z "${DYTOY_TUI_PID}" ]]; then
    dytoy_tui::start_next
    return 0
  fi
  kill -0 "${DYTOY_TUI_PID}" 2> /dev/null && return 0

  local status=0 index="${DYTOY_TUI_CURRENT}"
  wait "${DYTOY_TUI_PID}" 2> /dev/null || status=$?
  DYTOY_TUI_PID=""
  DYTOY_TUI_ELAPSED[index]=$((EPOCHSECONDS - DYTOY_TUI_STARTED[index]))
  if ((status == 0)); then
    DYTOY_TUI_STATE[index]="ok"
  else
    DYTOY_TUI_STATE[index]="failed"
    printf '\n[exit status %s]\n' "${status}" >> "${DYTOY_TUI_LOG[index]}"
  fi
  dytoy_tui::start_next
}

#######################################
# @description Terminate the running child and everything it started. A child
# stopped on a read from the terminal only acts on the signal once continued.
# @noargs
#######################################
function dytoy_tui::kill_child {
  [[ -n "${DYTOY_TUI_PID}" ]] || return 0
  kill -TERM -- "-${DYTOY_TUI_PID}" 2> /dev/null || kill -TERM "${DYTOY_TUI_PID}" 2> /dev/null || true
  kill -CONT -- "-${DYTOY_TUI_PID}" 2> /dev/null || true
}

#######################################
# @description Stop the running tool and skip every tool not started yet.
# @noargs
#######################################
function dytoy_tui::stop {
  if [[ -n "${DYTOY_TUI_PID}" ]]; then
    dytoy_tui::kill_child
    wait "${DYTOY_TUI_PID}" 2> /dev/null || true
    DYTOY_TUI_PID=""
    local index="${DYTOY_TUI_CURRENT}"
    if ((index >= 0)); then
      DYTOY_TUI_STATE[index]="failed"
      DYTOY_TUI_ELAPSED[index]=$((EPOCHSECONDS - DYTOY_TUI_STARTED[index]))
      printf '\n[stopped]\n' >> "${DYTOY_TUI_LOG[index]}"
    fi
  fi
  local position
  for ((position = DYTOY_TUI_QUEUE_POS; position < ${#DYTOY_TUI_QUEUE[@]}; position++)); do
    DYTOY_TUI_STATE[DYTOY_TUI_QUEUE[position]]="skipped"
  done
  DYTOY_TUI_QUEUE_POS="${#DYTOY_TUI_QUEUE[@]}"
  DYTOY_TUI_PHASE="done"
  DYTOY_TUI_CURRENT=-1
}

#######################################
# @description Give the terminal back, keeping stderr. `dybatpho::screen_end`
# closes its terminal with `exec {fd}>&- 2> /dev/null`, and an `exec` without a
# command keeps its redirections, so every message after it would be lost.
# @noargs
#######################################
function dytoy_tui::screen_end {
  local stderr
  exec {stderr}>&2
  dybatpho::screen_end
  exec 2>&"${stderr}" {stderr}>&-
}

#######################################
# @description Return success when a picked tool installs with the package
# manager, which is what runs `sudo`.
# @noargs
#######################################
function dytoy_tui::needs_sudo {
  dybatpho::is true "${DRY_RUN}" && return 1
  dybatpho::is_root && return 1
  dybatpho::is command sudo || return 1
  local index
  for index in "${DYTOY_TUI_QUEUE[@]}"; do
    [[ "${DYTOY_TUI_METHOD[index]}" == "os" ]] && return 0
  done
  return 1
}

#######################################
# @description Make `sudo` usable from the children without a prompt. The
# password is asked for once, outside the interface, and kept fresh in the
# background; the children then find a `sudo` that refuses rather than asks,
# because a prompt drawn over the frame can be neither seen nor answered.
# @noargs
# @exitcode 1 Authentication was needed and failed
#######################################
function dytoy_tui::prepare_sudo {
  dybatpho::is command sudo || return 0
  dybatpho::is_root && return 0

  if dytoy_tui::needs_sudo; then
    dytoy_tui::screen_end
    printf 'dytoy needs sudo to install packages.\n' >&2
    local status=0
    sudo -v || status=$?
    dybatpho::screen_begin || return 1
    ((status == 0)) || return 1
    (
      while kill -0 "$$" 2> /dev/null; do
        sudo -n -v 2> /dev/null || true
        sleep 60
      done
    ) > /dev/null 2>&1 < /dev/null &
    DYTOY_TUI_KEEPALIVE_PID=$!
  fi

  local real_sudo
  real_sudo="$(command -v sudo)"
  DYTOY_TUI_WRAP_DIR="$(dybatpho::path_join "${DYTOY_TUI_LOG_DIR}" ".bin")"
  mkdir -p -- "${DYTOY_TUI_WRAP_DIR}"
  printf '#!/bin/sh\nexec %q -n "$@"\n' "${real_sudo}" > "${DYTOY_TUI_WRAP_DIR}/sudo"
  chmod +x "${DYTOY_TUI_WRAP_DIR}/sudo"
}

#######################################
# @description Stop whatever is still running when the interface ends,
# however it ends.
# @noargs
#######################################
function dytoy_tui::cleanup {
  if [[ -n "${DYTOY_TUI_PID}" ]]; then
    dytoy_tui::kill_child
    DYTOY_TUI_PID=""
  fi
  if [[ -n "${DYTOY_TUI_KEEPALIVE_PID}" ]]; then
    kill "${DYTOY_TUI_KEEPALIVE_PID}" 2> /dev/null || true
    DYTOY_TUI_KEEPALIVE_PID=""
  fi
  return 0
}

#######################################
# @description Print what happened, once the terminal is back.
# @noargs
# @set DYTOY_TUI_FAILED `true` when a tool failed or was stopped
#######################################
function dytoy_tui::summary {
  ((${#DYTOY_TUI_QUEUE[@]} > 0)) || return 0
  local index
  for index in "${DYTOY_TUI_QUEUE[@]}"; do
    case "${DYTOY_TUI_STATE[index]}" in
      ok) dybatpho::success "Installed ${DYTOY_TUI_METHOD[index]} tool: ${DYTOY_TUI_NAME[index]}" ;;
      skipped) dybatpho::warn "Skipped ${DYTOY_TUI_METHOD[index]} tool: ${DYTOY_TUI_NAME[index]}" ;;
      *)
        # shellcheck disable=SC2034
        DYTOY_TUI_FAILED=true
        dybatpho::error "Failed ${DYTOY_TUI_METHOD[index]} tool: ${DYTOY_TUI_NAME[index]}, see ${DYTOY_TUI_LOG[index]}"
        ;;
    esac
  done
}

#######################################
# @description Run the interface: pick tools, install them, and report.
# @arg $1 string Path of the `dytoy` executable the children run
# @set DYTOY_TUI_FAILED `true` when a tool failed or was stopped
# @exitcode 1 There is no terminal to take over
#######################################
function dytoy_tui::run {
  local self
  dybatpho::expect_args self -- "$@"
  DYTOY_TUI_SELF="${self}"
  DYTOY_TUI_LOG_DIR="$(dybatpho::path_join "$(dybatpho::xdg_state_dir dytoy)" "logs" "$(date +%Y%m%d-%H%M%S)")"

  dybatpho::progress "Reading $(dytoy::yaml_file)"
  dytoy_tui::load_tools

  # Mouse reporting would take text selection away from the log pane.
  # shellcheck disable=SC2034 # read by dybatpho::screen_begin
  DYBATPHO_SCREEN_MOUSE=false
  dybatpho::screen_begin || return 1
  dybatpho::trap "dytoy_tui::cleanup" EXIT INT TERM

  local key
  while dybatpho::is true "${DYTOY_TUI_RUNNING}"; do
    dytoy_tui::draw
    dybatpho::screen_flush
    if [[ "${DYTOY_TUI_PHASE}" == "pick" ]]; then
      dybatpho::screen_event key || continue
      dytoy_tui::handle_pick_key "${key}"
      # A frame takes longer to draw than a held key takes to repeat, so every
      # key already waiting is handled before the next one is drawn; otherwise
      # the cursor keeps moving long after the key is released.
      while [[ "${DYTOY_TUI_PHASE}" == "pick" ]] \
        && dybatpho::is true "${DYTOY_TUI_RUNNING}" \
        && dybatpho::screen_pending; do
        dybatpho::screen_event key || break
        dytoy_tui::handle_pick_key "${key}"
      done
      if [[ "${DYTOY_TUI_PHASE}" == "install" ]]; then
        # The logs are the interface's own, so they are written in a dry run
        # too, where `dybatpho::ensure_dir` would only say it creates them.
        mkdir -p -- "${DYTOY_TUI_LOG_DIR}"
        dytoy_tui::build_queue
        if ! dytoy_tui::prepare_sudo; then
          DYTOY_TUI_PHASE="pick"
          DYTOY_TUI_QUEUE=()
          DYTOY_TUI_STATUS="sudo authentication failed, nothing was installed"
        fi
      fi
      continue
    fi
    # The deadline keeps the spinner and the log moving while no key comes.
    if dybatpho::screen_event key 0.1; then
      dytoy_tui::handle_install_key "${key}"
      while dybatpho::is true "${DYTOY_TUI_RUNNING}" && dybatpho::screen_pending; do
        dybatpho::screen_event key || break
        dytoy_tui::handle_install_key "${key}"
      done
    fi
    dytoy_tui::poll
  done

  dytoy_tui::screen_end
  dytoy_tui::cleanup
  dytoy_tui::summary
}
