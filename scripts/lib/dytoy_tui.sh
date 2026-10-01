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
# `true` for a tool left out of the list by `--essential`; it is still loaded
# so a listed tool can depend on it.
declare -ga DYTOY_TUI_HIDDEN=()
# The dependencies each tool declares, comma-separated names.
declare -ga DYTOY_TUI_DEPS=()
# The index of each tool, by name.
declare -gA DYTOY_TUI_INDEX=()
# The stage a queued tool installs in: `dependencies` for one installed ahead
# of the others, otherwise its method.
declare -ga DYTOY_TUI_STAGE=()
# `pending`, `running`, `ok`, `failed`, or `skipped`.
declare -ga DYTOY_TUI_STATE=()
declare -ga DYTOY_TUI_LOG=()
declare -ga DYTOY_TUI_STARTED=()
declare -ga DYTOY_TUI_ELAPSED=()
# The YAML of each tool by index, read on first view.
declare -gA DYTOY_TUI_DETAIL=()
# The cursor of each pick tab, by method.
declare -gA DYTOY_TUI_CURSOR=()
# The first row each list shows, by list.
declare -gA DYTOY_TUI_OFFSET=()

# Indexes of the picked tools, in the order they install.
declare -ga DYTOY_TUI_QUEUE=()
DYTOY_TUI_QUEUE_POS=0
# The process of each running tool, by index.
declare -gA DYTOY_TUI_PIDS=()
# How many tools run at once where their method allows it.
DYTOY_TUI_JOBS=4
# The tool whose log is shown, as a position in the queue.
DYTOY_TUI_VIEW=0
DYTOY_TUI_FOLLOW=true

# `pick`, `install`, or `done`.
DYTOY_TUI_PHASE="pick"
# `normal`, `search` while a name is being typed in the pick phase, or
# `confirm` while the stop dialog is up.
DYTOY_TUI_MODE="normal"
# What is typed in search mode, and the cursor among the tools it matches.
DYTOY_TUI_QUERY=""
DYTOY_TUI_MATCH=0
DYTOY_TUI_TAB=0
DYTOY_TUI_RUNNING=true
DYTOY_TUI_STATUS=""
DYTOY_TUI_SELF=""
DYTOY_TUI_LOG_DIR=""
DYTOY_TUI_WRAP_DIR=""
DYTOY_TUI_KEEPALIVE_PID=""

declare -ga DYTOY_TUI_SPINNER=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
# The Catppuccin palette the theme is built from, by colour name. Macchiato is
# the default; the installed `dytoy` replaces it with the flavour chezmoi
# renders, so the interface matches the terminal.
declare -gA DYTOY_TUI_PALETTE=(
  [rosewater]="#f4dbd6" [flamingo]="#f0c6c6" [pink]="#f5bde6" [mauve]="#c6a0f6"
  [red]="#ed8796" [maroon]="#ee99a0" [peach]="#f5a97f" [yellow]="#eed49f"
  [green]="#a6da95" [teal]="#8bd5ca" [sky]="#91d7e3" [sapphire]="#7dc4e4"
  [blue]="#8aadf4" [lavender]="#b7bdf8" [text]="#cad3f5" [subtext1]="#b8c0e0"
  [subtext0]="#a5adcb" [overlay2]="#939ab7" [overlay1]="#8087a2" [overlay0]="#6e738d"
  [surface2]="#5b6078" [surface1]="#494d64" [surface0]="#363a4f" [base]="#24273a"
  [mantle]="#1e2030" [crust]="#181926"
)
# The source file each tool is defined in, by name; the installed `dytoy`
# fills it, and a tool missing from it cannot be edited from the interface.
declare -gA DYTOY_TUI_SOURCE=()
# The terminal the editor runs on while the interface is suspended.
DYTOY_TUI_TTY="/dev/tty"
# The styles only this interface draws, set by dytoy_tui::theme; every other
# style is a `DYBATPHO_SCREEN_STYLE_*` of the screen module's theme.
DYTOY_TUI_STYLE_BRAND="" DYTOY_TUI_STYLE_ROW_BG="" DYTOY_TUI_STYLE_TEXT=""
DYTOY_TUI_STYLE_STRONG="" DYTOY_TUI_STYLE_RUN="" DYTOY_TUI_STYLE_KEY=""
DYTOY_TUI_STYLE_VALUE="" DYTOY_TUI_STYLE_GAUGE_EMPTY="" DYTOY_TUI_STYLE_BADGE=""
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
# @set DYTOY_TUI_HIDDEN, DYTOY_TUI_DEPS, DYTOY_TUI_INDEX
#######################################
function dytoy_tui::load_tools {
  DYTOY_TUI_HIDDEN=()
  DYTOY_TUI_DEPS=()
  DYTOY_TUI_INDEX=()
  DYTOY_TUI_STAGE=()
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
  local rows yaml_file
  yaml_file="$(dytoy::yaml_file)"
  rows=$(dybatpho::yaml_query "${yaml_file}" \
    'explode(.) | .[] | select(.enabled != false and .enabled != "false")
      | [.name, .method, (.is_essential // false), ((.dependencies // []) | join(","))] | @tsv' -r)

  local method name tool_method essential dependencies installed hidden
  for method in "${DYTOY_METHODS[@]}"; do
    while IFS=$'\t' read -r name tool_method essential dependencies; do
      [[ -n "${name}" && "${tool_method}" == "${method}" ]] || continue
      hidden=false
      if dybatpho::is true "${ONLY_ESSENTIAL}" && ! dybatpho::is true "${essential}"; then
        hidden=true
      fi
      installed="$(dytoy_tui::detect_installed "${name}" "${method}")"
      [[ -n "${DYTOY_TUI_INDEX[${name}]+set}" ]] || DYTOY_TUI_INDEX["${name}"]="${#DYTOY_TUI_NAME[@]}"
      DYTOY_TUI_HIDDEN+=("${hidden}")
      DYTOY_TUI_DEPS+=("${dependencies}")
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
  local local_bin_file
  local_bin_file="$(dybatpho::path_join "${HOME}" ".local" "bin" "${name}")"
  if [[ "${method}" == "os" ]]; then
    echo "unknown"
  elif dybatpho::is command "${name}" || dybatpho::is file "${local_bin_file}"; then
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
  local __dytoy_tui_items_ref method index
  dybatpho::expect_args __dytoy_tui_items_ref method -- "$@"
  local -n __dytoy_tui_items="${__dytoy_tui_items_ref}"
  __dytoy_tui_items=()
  for index in "${!DYTOY_TUI_NAME[@]}"; do
    dybatpho::is true "${DYTOY_TUI_HIDDEN[index]}" && continue
    [[ "${DYTOY_TUI_METHOD[index]}" == "${method}" ]] && __dytoy_tui_items+=("${index}")
  done
  return 0
}

#######################################
# @description Fill an array with the indexes of the tools whose name holds
# the search query, across every method, in install order. The match is a
# case-insensitive substring rather than a pattern: a search is typed in a
# hurry and should not need escaping.
# @arg $1 string Name of the array variable receiving the indexes
# @env DYTOY_TUI_QUERY string What was typed
#######################################
function dytoy_tui::search_matches {
  local __dytoy_tui_matches_ref
  dybatpho::expect_args __dytoy_tui_matches_ref -- "$@"
  local -n __dytoy_tui_matches="${__dytoy_tui_matches_ref}"
  local query="${DYTOY_TUI_QUERY,,}" index
  __dytoy_tui_matches=()
  for index in "${!DYTOY_TUI_NAME[@]}"; do
    dybatpho::is true "${DYTOY_TUI_HIDDEN[index]}" && continue
    [[ "${DYTOY_TUI_NAME[index],,}" == *"${query}"* ]] && __dytoy_tui_matches+=("${index}")
  done
  return 0
}

#######################################
# @description Pick a tool, or unpick it when it is already picked.
# @arg $1 number Index of the tool
#######################################
function dytoy_tui::toggle_pick {
  local index
  dybatpho::expect_args index -- "$@"
  if dybatpho::is true "${DYTOY_TUI_PICKED[index]}"; then
    DYTOY_TUI_PICKED[index]=false
  else
    DYTOY_TUI_PICKED[index]=true
  fi
}

#######################################
# @description Count the picked tools, overall or for one method. It is asked
# once per tab on every frame, so it writes to a variable rather than paying
# for a subshell each time: a frame that forks falls behind a held key.
# @arg $1 string Name of the variable receiving the count
# @arg $2 string Method, or empty for every method
#######################################
function dytoy_tui::picked_count_into {
  local __dytoy_tui_picked_ref method index
  dybatpho::expect_args __dytoy_tui_picked_ref method -- "$@"
  local -n __dytoy_tui_picked="${__dytoy_tui_picked_ref}"
  __dytoy_tui_picked=0
  for index in "${!DYTOY_TUI_NAME[@]}"; do
    [[ -z "${method}" || "${DYTOY_TUI_METHOD[index]}" == "${method}" ]] || continue
    dybatpho::is true "${DYTOY_TUI_PICKED[index]}" && __dytoy_tui_picked=$((__dytoy_tui_picked + 1))
  done
  return 0
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
  local __dytoy_tui_args_ref index sync
  dybatpho::expect_args __dytoy_tui_args_ref index sync -- "$@"
  local -n __dytoy_tui_args="${__dytoy_tui_args_ref}"
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
# screen: colours kept, every other escape sequence dropped, a line redrawn
# with `\r` reduced to what it ended as, and tabs expanded.
# @arg $1 string Name of the array variable receiving the lines
# @arg $2 string Log file
# @arg $3 number Number of lines
#######################################
function dytoy_tui::log_tail {
  local __dytoy_tui_lines_ref file count
  dybatpho::expect_args __dytoy_tui_lines_ref file count -- "$@"
  local -n __dytoy_tui_lines="${__dytoy_tui_lines_ref}"
  __dytoy_tui_lines=()
  [[ -f "${file}" ]] && ((count > 0)) || return 0
  local tailed cleaned
  tailed="$(tail -n "${count}" "${file}")"
  [[ -n "${tailed}" ]] || return 0
  cleaned="$(LC_ALL=C sed -E \
    -e 's/\x1B\[[0-9;?]*[A-Za-ln-z]//g' \
    -e 's/\x1B\][^\x07]*\x07//g' \
    -e 's/\r$//' -e 's/.*\r//' \
    -e 's/\t/  /g' \
    -e 's/[\x01-\x08\x0B-\x1A\x1C-\x1F\x7F]//g' <<< "${tailed}")"
  [[ -n "${cleaned}" ]] || return 0
  readarray -t __dytoy_tui_lines <<< "${cleaned}"
}

#######################################
# @description Fill an array with every tool a tool depends on, directly or
# through another dependency, by index. A dependency that is not an enabled
# tool of the YAML file is left to the child, which reports it.
# @arg $1 string Name of the array variable receiving the indexes
# @arg $2 number Index of the tool
#######################################
function dytoy_tui::dependency_closure_into {
  local __dytoy_tui_closure_ref start
  dybatpho::expect_args __dytoy_tui_closure_ref start -- "$@"
  local -n __dytoy_tui_closure="${__dytoy_tui_closure_ref}"
  __dytoy_tui_closure=()
  local -A seen=(["${start}"]=1)
  local -a pending=("${start}")
  local index name dependency
  local -a names=()
  while ((${#pending[@]} > 0)); do
    index="${pending[0]}"
    pending=("${pending[@]:1}")
    IFS=, read -r -a names <<< "${DYTOY_TUI_DEPS[index]}"
    for name in "${names[@]}"; do
      dependency="${DYTOY_TUI_INDEX[${name}]-}"
      [[ -n "${dependency}" && -z "${seen[${dependency}]-}" ]] || continue
      seen["${dependency}"]=1
      __dytoy_tui_closure+=("${dependency}")
      pending+=("${dependency}")
    done
  done
  return 0
}

#######################################
# @description Append a tool to the order the shared dependencies install in,
# after whatever it depends on, so a dependency of a dependency goes first.
# @arg $1 number Index of the tool
# @env __DYTOY_TUI_EARLY Tools installed ahead of the others, by index
# @set __DYTOY_TUI_ORDER The order, built up across calls
#######################################
function dytoy_tui::order_dependency {
  local index
  dybatpho::expect_args index -- "$@"
  [[ -z "${__DYTOY_TUI_VISITED[${index}]-}" ]] || return 0
  __DYTOY_TUI_VISITED["${index}"]=1
  local name dependency
  local -a names=()
  IFS=, read -r -a names <<< "${DYTOY_TUI_DEPS[index]}"
  for name in "${names[@]}"; do
    dependency="${DYTOY_TUI_INDEX[${name}]-}"
    [[ -n "${dependency}" ]] && dytoy_tui::order_dependency "${dependency}"
  done
  [[ -n "${__DYTOY_TUI_EARLY[${index}]-}" ]] && __DYTOY_TUI_ORDER+=("${index}")
  return 0
}

#######################################
# @description Fill the queue with what is to be installed, in order, and
# reset its state.
#
# Tools of a method run side by side, and each child installs its own
# dependencies, so two tools needing the same one would both install it at
# once -- as would a tool and a picked tool it depends on. Those dependencies
# go first instead, in a stage of their own that runs one tool at a time: a
# dependency needed by two picked tools or more, directly or not, and a picked
# tool another picked tool depends on. The children then find them installed.
# @noargs
# @set DYTOY_TUI_QUEUE, DYTOY_TUI_STAGE
#######################################
function dytoy_tui::build_queue {
  DYTOY_TUI_QUEUE=()
  DYTOY_TUI_STAGE=()
  local index dependency
  local -a closure=()
  local -A needed_by=()
  declare -gA __DYTOY_TUI_EARLY=() __DYTOY_TUI_VISITED=()
  declare -ga __DYTOY_TUI_ORDER=()
  for index in "${!DYTOY_TUI_NAME[@]}"; do
    dybatpho::is true "${DYTOY_TUI_PICKED[index]}" || continue
    dytoy_tui::dependency_closure_into closure "${index}"
    for dependency in "${closure[@]}"; do
      needed_by["${dependency}"]=$((${needed_by[${dependency}]:-0} + 1))
      dybatpho::is true "${DYTOY_TUI_PICKED[dependency]}" && __DYTOY_TUI_EARLY["${dependency}"]=1
    done
  done
  for dependency in "${!needed_by[@]}"; do
    ((needed_by[${dependency}] >= 2)) && __DYTOY_TUI_EARLY["${dependency}"]=1
  done
  for index in "${!DYTOY_TUI_NAME[@]}"; do
    [[ -n "${__DYTOY_TUI_EARLY[${index}]-}" ]] && dytoy_tui::order_dependency "${index}"
  done

  for index in "${__DYTOY_TUI_ORDER[@]}"; do
    DYTOY_TUI_QUEUE+=("${index}")
    DYTOY_TUI_STAGE[index]="dependencies"
    DYTOY_TUI_STATE[index]="pending"
  done
  for index in "${!DYTOY_TUI_NAME[@]}"; do
    dybatpho::is true "${DYTOY_TUI_PICKED[index]}" || continue
    [[ -z "${__DYTOY_TUI_EARLY[${index}]-}" ]] || continue
    DYTOY_TUI_QUEUE+=("${index}")
    DYTOY_TUI_STAGE[index]="${DYTOY_TUI_METHOD[index]}"
    DYTOY_TUI_STATE[index]="pending"
  done
  unset __DYTOY_TUI_EARLY __DYTOY_TUI_VISITED __DYTOY_TUI_ORDER
  DYTOY_TUI_QUEUE_POS=0
  DYTOY_TUI_VIEW=0
  DYTOY_TUI_FOLLOW=true
  DYTOY_TUI_PIDS=()
}

#######################################
# @description Count the queued tools that ended in a state, into a variable
# rather than through a subshell, since every frame of the install phase asks.
# @arg $1 string Name of the variable receiving the count
# @arg $2 string State
#######################################
function dytoy_tui::count_state_into {
  local __dytoy_tui_state_count_ref state index
  dybatpho::expect_args __dytoy_tui_state_count_ref state -- "$@"
  local -n __dytoy_tui_state_count="${__dytoy_tui_state_count_ref}"
  __dytoy_tui_state_count=0
  for index in "${DYTOY_TUI_QUEUE[@]}"; do
    [[ "${DYTOY_TUI_STATE[index]}" == "${state}" ]] \
      && __dytoy_tui_state_count=$((__dytoy_tui_state_count + 1))
  done
  return 0
}

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

#######################################
# @description Set a variable to the SGR parameters of a palette colour, in
# 24-bit colour, as a foreground or a background.
# @arg $1 string Name of the variable receiving the parameters
# @arg $2 string `fg` or `bg`
# @arg $3 string Colour name in `DYTOY_TUI_PALETTE`
#######################################
function dytoy_tui::colour_into {
  local __dytoy_tui_colour_ref layer name
  dybatpho::expect_args __dytoy_tui_colour_ref layer name -- "$@"
  local -n __dytoy_tui_colour="${__dytoy_tui_colour_ref}"
  local hex="${DYTOY_TUI_PALETTE[${name}]-}"
  hex="${hex#\#}"
  [[ "${hex}" =~ ^[0-9a-fA-F]{6}$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: '${name}' is not a #rrggbb colour of the palette"
  local code=38
  [[ "${layer}" == bg ]] && code=48
  __dytoy_tui_colour="${code};2;$((16#${hex:0:2}));$((16#${hex:2:2}));$((16#${hex:4:2}))"
}

#######################################
# @description Set the colours of the interface from the Catppuccin palette
# in `DYTOY_TUI_PALETTE`, for the screen module's widgets and for the few
# styles only this interface draws. The palette is Macchiato unless the
# installed `dytoy` was rendered with another flavour. `NO_COLOR` gives the
# `mono` theme and leaves bold, dim and reverse to mark what matters.
# @noargs
# @env NO_COLOR string Draw without colours when set to a non-empty value
# @env DYTOY_TUI_PALETTE array Catppuccin colours by name, `#rrggbb`
#######################################
function dytoy_tui::theme {
  if [[ -n "${NO_COLOR:-}" ]]; then
    dybatpho::screen_theme mono
    DYTOY_TUI_STYLE_BRAND="1;7"
    DYTOY_TUI_STYLE_ROW_BG=""
    DYTOY_TUI_STYLE_TEXT="0"
    DYTOY_TUI_STYLE_STRONG="1"
    DYTOY_TUI_STYLE_RUN="1"
    DYTOY_TUI_STYLE_KEY="1"
    DYTOY_TUI_STYLE_VALUE="0"
    DYTOY_TUI_STYLE_GAUGE_EMPTY="2"
    DYTOY_TUI_STYLE_BADGE="1;7"
    return 0
  fi
  local text subtext1 overlay1 surface0 surface1 surface2 mantle crust
  local mauve pink lavender blue sky green yellow peach red
  local mauve_bg lavender_bg yellow_bg surface1_fg
  dytoy_tui::colour_into text fg text
  dytoy_tui::colour_into subtext1 fg subtext1
  dytoy_tui::colour_into overlay1 fg overlay1
  dytoy_tui::colour_into surface0 bg surface0
  dytoy_tui::colour_into surface1 bg surface1
  dytoy_tui::colour_into surface1_fg fg surface1
  dytoy_tui::colour_into surface2 fg surface2
  dytoy_tui::colour_into mantle bg mantle
  dytoy_tui::colour_into crust fg crust
  dytoy_tui::colour_into mauve fg mauve
  dytoy_tui::colour_into pink fg pink
  dytoy_tui::colour_into lavender fg lavender
  dytoy_tui::colour_into blue fg blue
  dytoy_tui::colour_into sky fg sky
  dytoy_tui::colour_into green fg green
  dytoy_tui::colour_into yellow fg yellow
  dytoy_tui::colour_into peach fg peach
  dytoy_tui::colour_into red fg red
  dytoy_tui::colour_into mauve_bg bg mauve
  dytoy_tui::colour_into lavender_bg bg lavender
  dytoy_tui::colour_into yellow_bg bg yellow

  # The screen module's widgets: frames, selection, tabs, the key bar. They are
  # exported, as the screen module declares them, since its widgets read them.
  export DYBATPHO_SCREEN_STYLE_SELECTED="1;${text};${surface1}"
  export DYBATPHO_SCREEN_STYLE_BORDER="${surface2}"
  export DYBATPHO_SCREEN_STYLE_FOCUS="${mauve}"
  export DYBATPHO_SCREEN_STYLE_TITLE="1;${lavender}"
  export DYBATPHO_SCREEN_STYLE_TAB_ACTIVE="1;${crust};${lavender_bg}"
  export DYBATPHO_SCREEN_STYLE_KEYBAR="${subtext1};${mantle}"
  export DYBATPHO_SCREEN_STYLE_KEY="1;${mauve}"
  export DYBATPHO_SCREEN_STYLE_ACCENT="1;${pink}"
  export DYBATPHO_SCREEN_STYLE_DIM="${overlay1}"
  export DYBATPHO_SCREEN_STYLE_OK="1;${green}"
  export DYBATPHO_SCREEN_STYLE_WARN="${yellow}"
  export DYBATPHO_SCREEN_STYLE_ERROR="1;${red}"

  # What only this interface draws.
  DYTOY_TUI_STYLE_BRAND="1;${crust};${mauve_bg}"
  DYTOY_TUI_STYLE_ROW_BG="${surface0}"
  DYTOY_TUI_STYLE_TEXT="${text}"
  DYTOY_TUI_STYLE_STRONG="1;${text}"
  DYTOY_TUI_STYLE_RUN="1;${sky}"
  DYTOY_TUI_STYLE_KEY="${blue}"
  DYTOY_TUI_STYLE_VALUE="${peach}"
  DYTOY_TUI_STYLE_GAUGE_EMPTY="${surface1_fg}"
  DYTOY_TUI_STYLE_BADGE="1;${crust};${yellow_bg}"
}

#######################################
# @description Draw one line of YAML with its keys, values and comments
# coloured apart.
# @arg $1 number Row
# @arg $2 number Column
# @arg $3 number Width
# @arg $4 string The line
#######################################
function dytoy_tui::put_yaml {
  local row column width line
  dybatpho::expect_args row column width line -- "$@"
  local value_style="${DYTOY_TUI_STYLE_VALUE}"
  if [[ "${line}" =~ ^([[:space:]]*)#(.*)$ ]]; then
    dybatpho::screen_spans "${row}" "${column}" "${width}" "" "${line}" "${DYBATPHO_SCREEN_STYLE_DIM}"
  elif [[ "${line}" =~ ^([[:space:]]*)(-[[:space:]]+)?([^:#[:space:]][^:]*):([[:space:]].*)?$ ]]; then
    # The groups are copied first: the test on the value below replaces them.
    local indent="${BASH_REMATCH[1]}" dash="${BASH_REMATCH[2]-}" key="${BASH_REMATCH[3]}"
    local value="${BASH_REMATCH[4]-}"
    [[ "${value}" =~ ^[[:space:]]*(true|false|null|-?[0-9.]+)$ ]] && value_style="${DYBATPHO_SCREEN_STYLE_WARN}"
    dybatpho::screen_spans "${row}" "${column}" "${width}" "" \
      "${indent}" "0" \
      "${dash}" "${DYBATPHO_SCREEN_STYLE_DIM}" \
      "${key}" "${DYTOY_TUI_STYLE_KEY}" \
      ":" "${DYBATPHO_SCREEN_STYLE_DIM}" \
      "${value}" "${value_style}"
  elif [[ "${line}" =~ ^([[:space:]]*)(-[[:space:]]+)(.*)$ ]]; then
    dybatpho::screen_spans "${row}" "${column}" "${width}" "" \
      "${BASH_REMATCH[1]}" "0" \
      "${BASH_REMATCH[2]}" "${DYBATPHO_SCREEN_STYLE_DIM}" \
      "${BASH_REMATCH[3]}" "${value_style}"
  else
    dybatpho::screen_spans "${row}" "${column}" "${width}" "" "${line}" "${value_style}"
  fi
}

#######################################
# @description Work out the first row a list shows, scrolling only as far as
# keeps the selection in view, so moving the cursor does not jerk the list.
# @arg $1 string Key the offset is remembered under
# @arg $2 number Selected item
# @arg $3 number Number of items
# @arg $4 number Rows available
# @set DYTOY_TUI_OFFSET The offset, under the key
#######################################
function dytoy_tui::scroll {
  local key selected count height
  dybatpho::expect_args key selected count height -- "$@"
  local offset="${DYTOY_TUI_OFFSET[${key}]:-0}"
  ((selected < offset)) && offset="${selected}"
  ((selected >= offset + height)) && offset=$((selected - height + 1))
  ((offset > count - height)) && offset=$((count - height))
  ((offset >= 0)) || offset=0
  DYTOY_TUI_OFFSET["${key}"]="${offset}"
}

#######################################
# @description Draw a bordered panel, highlighted when it has the focus.
# @arg $1 string Rectangle
# @arg $2 string Title
# @arg $3 boolean Whether the panel has the focus
# @set DYBATPHO_SCREEN_INNER The rectangle inside the border
#######################################
function dytoy_tui::panel {
  local rect title focus
  dybatpho::expect_args rect title focus -- "$@"
  dybatpho::screen_block "${rect}" title:"${title}" border:rounded focus:"${focus}"
}

#######################################
# @description Draw the top row: the name of the tool, then either the method
# tabs or what is being done, and a badge for a dry run.
# @arg $1 string Rectangle
# @arg $@ string Pairs of text and SGR parameters drawn after the name
#######################################
function dytoy_tui::draw_header {
  local rect x y width
  dybatpho::expect_args rect -- "$@"
  shift
  read -r x y width _ <<< "${rect}"
  local -a segments=(" ◆ dytoy " "${DYTOY_TUI_STYLE_BRAND}" "  " "0" "$@")
  local badge=""
  dybatpho::is true "${DRY_RUN}" && badge=" DRY RUN "
  dybatpho::screen_spans "${y}" "${x}" "$((width - ${#badge}))" "" "${segments[@]}"
  [[ -n "${badge}" ]] && dybatpho::screen_put "${y}" "$((x + width - ${#badge}))" "${badge}" "${DYTOY_TUI_STYLE_BADGE}"
  return 0
}

#######################################
# @description Draw the bottom row: key hints, or a message when there is one.
# @arg $1 string Rectangle
# @arg $@ string Pairs of a key and what it does
#######################################
function dytoy_tui::draw_footer {
  local rect
  dybatpho::expect_args rect -- "$@"
  shift
  if [[ -z "${DYTOY_TUI_STATUS}" ]]; then
    dybatpho::screen_keybar "${rect}" "$@"
    return 0
  fi
  local x y width
  read -r x y width _ <<< "${rect}"
  dybatpho::screen_spans "${y}" "${x}" "${width}" "${DYBATPHO_SCREEN_STYLE_KEYBAR}" \
    " ! ${DYTOY_TUI_STATUS}" "1;${DYBATPHO_SCREEN_STYLE_WARN}"
}

#######################################
# @description Draw a thin progress bar with its label after it.
# @arg $1 string Rectangle, only its first row is used
# @arg $2 number Value reached
# @arg $3 number Value that counts as full
# @arg $4 string SGR parameters of the filled part
# @arg $5 string Label
#######################################
function dytoy_tui::draw_progress {
  local rect value total style label x y width label_width
  dybatpho::expect_args rect value total style label -- "$@"
  read -r x y width _ <<< "${rect}"
  ((total > 0)) || total=1
  dybatpho::screen_width label_width "${label}"
  local bar_width=$((width - label_width - 2))
  ((bar_width > 4)) || bar_width=4
  local filled=$((value * bar_width / total)) full="" empty=""
  printf -v full '%*s' "${filled}" ""
  printf -v empty '%*s' "$((bar_width - filled))" ""
  dybatpho::screen_spans "${y}" "${x}" "${width}" "" \
    "${full// /━}" "${style}" "${empty// /─}" "${DYTOY_TUI_STYLE_GAUGE_EMPTY}" \
    "  ${label}" "${DYTOY_TUI_STYLE_STRONG}"
}

#######################################
# @description Read the YAML of a tool, once, and remember it.
# @arg $1 number Index of the tool
# @set DYTOY_TUI_DETAIL The YAML of the tool
#######################################
function dytoy_tui::load_detail {
  local index
  dybatpho::expect_args index -- "$@"
  [[ -n "${DYTOY_TUI_DETAIL[${index}]+set}" ]] && return 0
  local yaml_file
  yaml_file="$(dytoy::yaml_file)"
  DYTOY_TUI_DETAIL["${index}"]="$(dybatpho::yaml_query "${yaml_file}" \
    "explode(.) | .[] | select(.name == \"${DYTOY_TUI_NAME[index]}\" and .method == \"${DYTOY_TUI_METHOD[index]}\")" \
    2> /dev/null)" || DYTOY_TUI_DETAIL["${index}"]=""
}

#######################################
# @description Draw the pick phase into the buffer.
# @noargs
#######################################
function dytoy_tui::draw_pick {
  local -a frame=() body=() items=() tabs=()
  dybatpho::screen_layout frame vertical "${DYBATPHO_SCREEN_RECT}" length:1 fill:1 length:1

  local method position style picked
  for position in "${!DYTOY_METHODS[@]}"; do
    method="${DYTOY_METHODS[position]}"
    dytoy_tui::tab_items items "${method}"
    dytoy_tui::picked_count_into picked "${method}"
    style="${DYTOY_TUI_STYLE_TEXT}"
    ((position == DYTOY_TUI_TAB)) && style="${DYBATPHO_SCREEN_STYLE_TAB_ACTIVE}"
    tabs+=(" ${method} ${picked}/${#items[@]} " "${style}" " " "0")
  done
  dytoy_tui::draw_header "${frame[0]}" "${tabs[@]}"

  # Search mode lists what matches across every method, each with its method
  # in front; otherwise the list is the tools of the current tab.
  method="${DYTOY_METHODS[DYTOY_TUI_TAB]}"
  local cursor list_key title="Tools" empty="No ${method} tool to install" searching=false
  if [[ "${DYTOY_TUI_MODE}" == "search" ]]; then
    searching=true
    dytoy_tui::search_matches items
    cursor="${DYTOY_TUI_MATCH}" list_key="search" title="Search"
    empty="No tool matches '${DYTOY_TUI_QUERY}'"
  else
    dytoy_tui::tab_items items "${method}"
    cursor="${DYTOY_TUI_CURSOR[${method}]:-0}" list_key="pick:${method}"
  fi
  local count="${#items[@]}"

  dybatpho::screen_layout body horizontal "${frame[1]}" percent:40 fill:1
  dytoy_tui::panel "${body[0]}" "${title}" true
  local x y width height
  read -r x y width height <<< "${DYBATPHO_SCREEN_INNER}"
  if ((count == 0)); then
    dybatpho::screen_text "${DYBATPHO_SCREEN_INNER}" "${empty}" \
      align:center style:"${DYBATPHO_SCREEN_STYLE_DIM}"
  else
    # A scrollbar takes the last column only when the list overflows.
    local list_width="${width}"
    ((count > height)) && list_width=$((width - 1))
    dytoy_tui::scroll "${list_key}" "${cursor}" "${count}" "${height}"
    local offset="${DYTOY_TUI_OFFSET[${list_key}]}" row index
    local background pointer box box_style mark mark_style name_style star prefix
    for ((row = 0; row < height && offset + row < count; row++)); do
      index="${items[offset + row]}"
      background="" pointer="  " name_style="${DYTOY_TUI_STYLE_TEXT}"
      if ((offset + row == cursor)); then
        background="${DYTOY_TUI_STYLE_ROW_BG}" pointer="▌ " name_style="${DYTOY_TUI_STYLE_STRONG}"
      fi
      box="[ ]" box_style="${DYBATPHO_SCREEN_STYLE_DIM}"
      dybatpho::is true "${DYTOY_TUI_PICKED[index]}" && box="[✔]" box_style="${DYBATPHO_SCREEN_STYLE_OK}"
      case "${DYTOY_TUI_INSTALLED[index]}" in
        yes) mark="●" mark_style="${DYBATPHO_SCREEN_STYLE_OK}" ;;
        no) mark="○" mark_style="${DYBATPHO_SCREEN_STYLE_WARN}" ;;
        *) mark="◌" mark_style="${DYBATPHO_SCREEN_STYLE_DIM}" ;;
      esac
      star="" prefix=""
      dybatpho::is true "${DYTOY_TUI_ESSENTIAL[index]}" && star=" ★"
      dybatpho::is true "${searching}" && prefix="${DYTOY_TUI_METHOD[index]}/"
      dybatpho::screen_spans "$((y + row))" "${x}" "${list_width}" "${background}" \
        "${pointer}" "${DYBATPHO_SCREEN_STYLE_ACCENT}" \
        "${box}" "${box_style}" " " "0" \
        "${mark}" "${mark_style}" " " "0" \
        "${prefix}" "${DYBATPHO_SCREEN_STYLE_DIM}" \
        "${DYTOY_TUI_NAME[index]}" "${name_style}" \
        "${star}" "${DYBATPHO_SCREEN_STYLE_WARN}"
    done
    if ((count > height)); then
      local bar_rect
      dybatpho::screen_rect bar_rect "$((x + width - 1))" "${y}" 1 "${height}"
      dybatpho::screen_scrollbar "${bar_rect}" "${offset}" "${count}" \
        style:"${DYBATPHO_SCREEN_STYLE_FOCUS}" track_style:"${DYBATPHO_SCREEN_STYLE_BORDER}"
    fi
  fi

  if ((count > 0)); then
    local selected="${items[cursor]}"
    dytoy_tui::panel "${body[1]}" "${DYTOY_TUI_NAME[selected]}" false
    read -r x y width height <<< "${DYBATPHO_SCREEN_INNER}"
    dytoy_tui::load_detail "${selected}"
    local -a detail=()
    readarray -t detail <<< "${DYTOY_TUI_DETAIL[${selected}]}"
    for ((row = 0; row < height && row < ${#detail[@]}; row++)); do
      dytoy_tui::put_yaml "$((y + row))" "$((x + 1))" "$((width - 1))" "${detail[row]}"
    done
  else
    dytoy_tui::panel "${body[1]}" "Details" false
  fi

  if dybatpho::is true "${searching}"; then
    read -r x y width _ <<< "${frame[2]}"
    dybatpho::screen_spans "${y}" "${x}" "${width}" "${DYBATPHO_SCREEN_STYLE_KEYBAR}" \
      " / " "${DYBATPHO_SCREEN_STYLE_KEY}" "${DYTOY_TUI_QUERY}" "${DYTOY_TUI_STYLE_STRONG}" \
      "▏" "${DYBATPHO_SCREEN_STYLE_ACCENT}" "   ${count} found " "" \
      " ↑↓" "${DYBATPHO_SCREEN_STYLE_KEY}" " move " "" " space" "${DYBATPHO_SCREEN_STYLE_KEY}" " pick " "" \
      " enter" "${DYBATPHO_SCREEN_STYLE_KEY}" " go to " "" " esc" "${DYBATPHO_SCREEN_STYLE_KEY}" " cancel " ""
    return 0
  fi
  local total_picked
  dytoy_tui::picked_count_into total_picked ""
  dytoy_tui::draw_footer "${frame[2]}" \
    "space" "pick" "f" "find" "e" "edit" "a" "all" "←→" "tab" "enter" "install ${total_picked}" "q" "quit" \
    "●" "installed" "○" "missing" "★" "essential"
}

#######################################
# @description Set a variable to the marker of a queued tool's state, and
# another to its style. It is drawn once per tool per frame, so it writes to
# variables rather than paying for a subshell each time.
# @arg $1 string Name of the variable receiving the marker
# @arg $2 string Name of the variable receiving the style
# @arg $3 number Index of the tool
#######################################
function dytoy_tui::state_mark_into {
  local __dytoy_tui_mark_ref __dytoy_tui_mark_style_ref index
  dybatpho::expect_args __dytoy_tui_mark_ref __dytoy_tui_mark_style_ref index -- "$@"
  local -n __dytoy_tui_mark="${__dytoy_tui_mark_ref}" __dytoy_tui_mark_style="${__dytoy_tui_mark_style_ref}"
  case "${DYTOY_TUI_STATE[index]}" in
    ok) __dytoy_tui_mark="✔" __dytoy_tui_mark_style="${DYBATPHO_SCREEN_STYLE_OK}" ;;
    failed) __dytoy_tui_mark="✘" __dytoy_tui_mark_style="${DYBATPHO_SCREEN_STYLE_ERROR}" ;;
    skipped) __dytoy_tui_mark="⊘" __dytoy_tui_mark_style="${DYBATPHO_SCREEN_STYLE_DIM}" ;;
    running)
      local tick="${EPOCHREALTIME/[.,]/}"
      __dytoy_tui_mark="${DYTOY_TUI_SPINNER[(tick / 100000) % ${#DYTOY_TUI_SPINNER[@]}]}"
      __dytoy_tui_mark_style="${DYTOY_TUI_STYLE_RUN}"
      ;;
    *) __dytoy_tui_mark="·" __dytoy_tui_mark_style="${DYBATPHO_SCREEN_STYLE_DIM}" ;;
  esac
}

#######################################
# @description Draw the install phase into the buffer.
# @noargs
#######################################
function dytoy_tui::draw_install {
  local -a frame=() body=() tail_lines=()
  dybatpho::screen_layout frame vertical "${DYBATPHO_SCREEN_RECT}" length:1 length:3 fill:1 length:1

  local total="${#DYTOY_TUI_QUEUE[@]}" ok failed skipped finished
  dytoy_tui::count_state_into ok ok
  dytoy_tui::count_state_into failed failed
  dytoy_tui::count_state_into skipped skipped
  finished=$((ok + failed + skipped))

  local title="Installing" title_style="${DYTOY_TUI_STYLE_RUN}" label gauge_style="${DYBATPHO_SCREEN_STYLE_FOCUS}"
  if [[ "${DYTOY_TUI_PHASE}" == "done" ]]; then
    title="Finished" title_style="${DYBATPHO_SCREEN_STYLE_OK}" gauge_style="${DYBATPHO_SCREEN_STYLE_OK}"
    label="${ok} installed, ${failed} failed, ${skipped} skipped"
  else
    label="${finished}/${total}  ${#DYTOY_TUI_PIDS[@]} running"
  fi
  ((failed > 0)) && title_style="${DYBATPHO_SCREEN_STYLE_ERROR}" gauge_style="${DYBATPHO_SCREEN_STYLE_ERROR}"
  dytoy_tui::draw_header "${frame[0]}" " ${title} " "${title_style}"

  dytoy_tui::panel "${frame[1]}" "Progress" false
  dytoy_tui::draw_progress "${DYBATPHO_SCREEN_INNER}" "${finished}" "${total}" "${gauge_style}" "${label}"

  dybatpho::screen_layout body horizontal "${frame[2]}" percent:32 fill:1
  dytoy_tui::panel "${body[0]}" "Tools" true
  local x y width height
  read -r x y width height <<< "${DYBATPHO_SCREEN_INNER}"
  dytoy_tui::scroll "install" "${DYTOY_TUI_VIEW}" "${total}" "${height}"
  local offset="${DYTOY_TUI_OFFSET[install]}" row index elapsed mark mark_style background pointer name_style role
  for ((row = 0; row < height && offset + row < total; row++)); do
    index="${DYTOY_TUI_QUEUE[offset + row]}"
    dytoy_tui::state_mark_into mark mark_style "${index}"
    background="" pointer="  " name_style="${DYTOY_TUI_STYLE_TEXT}"
    [[ "${DYTOY_TUI_STATE[index]}" == "running" ]] && name_style="${DYTOY_TUI_STYLE_RUN}"
    [[ "${DYTOY_TUI_STATE[index]}" == "skipped" ]] && name_style="${DYBATPHO_SCREEN_STYLE_DIM}"
    if ((offset + row == DYTOY_TUI_VIEW)); then
      background="${DYTOY_TUI_STYLE_ROW_BG}" pointer="▌ "
    fi
    role=""
    [[ "${DYTOY_TUI_STAGE[index]-}" == "dependencies" ]] && role=" · shared"
    elapsed=""
    case "${DYTOY_TUI_STATE[index]}" in
      running) elapsed=" $((EPOCHSECONDS - DYTOY_TUI_STARTED[index]))s" ;;
      ok | failed) elapsed=" ${DYTOY_TUI_ELAPSED[index]}s" ;;
      *) ;;
    esac
    dybatpho::screen_spans "$((y + row))" "${x}" "${width}" "${background}" \
      "${pointer}" "${DYBATPHO_SCREEN_STYLE_ACCENT}" \
      "${mark}" "${mark_style}" " " "0" \
      "${DYTOY_TUI_METHOD[index]}/" "${DYBATPHO_SCREEN_STYLE_DIM}" \
      "${DYTOY_TUI_NAME[index]}" "${name_style}" \
      "${elapsed}" "${DYBATPHO_SCREEN_STYLE_DIM}" \
      "${role}" "${DYBATPHO_SCREEN_STYLE_DIM}"
  done

  local viewed="${DYTOY_TUI_QUEUE[DYTOY_TUI_VIEW]:--1}" log_title="Log"
  ((viewed >= 0)) && log_title="Log · ${DYTOY_TUI_NAME[viewed]}"
  dybatpho::is true "${DYTOY_TUI_FOLLOW}" && log_title+=" · following"
  dytoy_tui::panel "${body[1]}" "${log_title}" false
  read -r x y width height <<< "${DYBATPHO_SCREEN_INNER}"
  if ((viewed >= 0)) && [[ -n "${DYTOY_TUI_LOG[viewed]}" ]]; then
    dytoy_tui::log_tail tail_lines "${DYTOY_TUI_LOG[viewed]}" "${height}"
    for row in "${!tail_lines[@]}"; do
      dybatpho::screen_ansi "$((y + row))" "$((x + 1))" "$((width - 1))" "${tail_lines[row]}"
    done
  else
    dybatpho::screen_text "${DYBATPHO_SCREEN_INNER}" "Waiting to start" \
      align:center style:"${DYBATPHO_SCREEN_STYLE_DIM}"
  fi

  if [[ "${DYTOY_TUI_PHASE}" == "done" ]]; then
    dytoy_tui::draw_footer "${frame[3]}" "↑↓" "view log" "q" "quit" "logs" "${DYTOY_TUI_LOG_DIR}"
  else
    dytoy_tui::draw_footer "${frame[3]}" "↑↓" "view log" "f" "follow" "q" "stop"
  fi

  if [[ "${DYTOY_TUI_MODE}" == "confirm" ]]; then
    local box
    dybatpho::screen_rect_center box "${DYBATPHO_SCREEN_RECT}" 46 7
    dybatpho::screen_popup "${box}" title:" Stop installing " border:double \
      style:"${DYBATPHO_SCREEN_STYLE_ERROR}" title_style:"${DYBATPHO_SCREEN_STYLE_ERROR}"
    read -r x y width height <<< "${DYBATPHO_SCREEN_INNER}"
    dybatpho::screen_text "${DYBATPHO_SCREEN_INNER}" \
      "Stop the running tools and skip the rest?" align:center style:"${DYTOY_TUI_STYLE_STRONG}"
    ((height >= 3)) && dybatpho::screen_spans "$((y + 2))" "$((x + (width - 26) / 2))" 26 "" \
      " y " "${DYTOY_TUI_STYLE_BADGE}" " stop    " "${DYTOY_TUI_STYLE_TEXT}" \
      " n " "${DYTOY_TUI_STYLE_BADGE}" " keep going" "${DYTOY_TUI_STYLE_TEXT}"
  fi
  return 0
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
  local key
  dybatpho::expect_args key -- "$@"
  if [[ "${DYTOY_TUI_MODE}" == "search" ]]; then
    dytoy_tui::handle_search_key "${key}"
    return 0
  fi
  local -a items=()
  local method="${DYTOY_METHODS[DYTOY_TUI_TAB]}" tab_count="${#DYTOY_METHODS[@]}"
  dytoy_tui::tab_items items "${method}"
  local count="${#items[@]}" cursor="${DYTOY_TUI_CURSOR[${method}]:-0}"
  DYTOY_TUI_STATUS=""

  case "${key}" in
    char:q | escape | eof) DYTOY_TUI_RUNNING=false ;;
    up | char:k) ((count > 0)) && cursor=$(((cursor - 1 + count) % count)) ;;
    down | char:j) ((count > 0)) && cursor=$(((cursor + 1) % count)) ;;
    home | char:g) cursor=0 ;;
    end | char:G) ((count > 0)) && cursor=$((count - 1)) ;;
    left | char:h) DYTOY_TUI_TAB=$(((DYTOY_TUI_TAB - 1 + tab_count) % tab_count)) ;;
    right | char:l | tab) DYTOY_TUI_TAB=$(((DYTOY_TUI_TAB + 1) % tab_count)) ;;
    space)
      if ((count > 0)); then
        dytoy_tui::toggle_pick "${items[cursor]}"
        cursor=$(((cursor + 1) % count))
      fi
      ;;
    char:e) ((count > 0)) && dytoy_tui::edit_source "${items[cursor]}" ;;
    char:f | char:/)
      DYTOY_TUI_MODE="search"
      DYTOY_TUI_QUERY=""
      DYTOY_TUI_MATCH=0
      ;;
    char:a)
      # Pick the whole tab, or clear it when it is already fully picked.
      local index value=false tab_picked
      dytoy_tui::picked_count_into tab_picked "${method}"
      ((tab_picked < count)) && value=true
      for index in "${items[@]}"; do
        DYTOY_TUI_PICKED[index]="${value}"
      done
      ;;
    enter)
      local total_picked
      dytoy_tui::picked_count_into total_picked ""
      if ((total_picked == 0)); then
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
# @description Open the source file of a tool in the editor, with the
# interface suspended, then show what the file now renders to.
#
# The file edited is the template under `.chezmoitemplates/dytoy/`, not the
# generated `tools.yaml`, which the next apply would overwrite. The children
# keep reading `tools.yaml`, so the change installs once it is applied; the
# status line says so.
# @arg $1 number Index of the tool
# @env VISUAL string Editor to run, before `EDITOR`
# @env EDITOR string Editor to run when `VISUAL` is unset, default `vi`
# @set DYTOY_TUI_STATUS What happened
#######################################
function dytoy_tui::edit_source {
  local index
  dybatpho::expect_args index -- "$@"
  local name="${DYTOY_TUI_NAME[index]}"
  local source="${DYTOY_TUI_SOURCE[${name}]-}"
  if [[ -z "${source}" ]] || ! dybatpho::is file "${source}"; then
    DYTOY_TUI_STATUS="No source file is known for ${name}"
    return 0
  fi
  # An editor is often given with arguments, such as `code --wait`.
  local -a editor=()
  read -r -a editor <<< "${VISUAL:-${EDITOR:-vi}}"

  dytoy_tui::screen_end
  # The editor gets the terminal itself, opened once for both directions,
  # whatever this script's own streams were redirected to.
  local status=0 tty
  exec {tty}<> "${DYTOY_TUI_TTY}"
  "${editor[@]}" "${source}" <&"${tty}" >&"${tty}" 2>&1 || status=$?
  exec {tty}>&-
  if ! dybatpho::screen_begin; then
    DYTOY_TUI_RUNNING=false
    return 0
  fi
  if ((status != 0)); then
    DYTOY_TUI_STATUS="${editor[0]} exited with ${status}, ${source##*/} may be unchanged"
    return 0
  fi

  # Show the edit straight away: render the template the way apply will.
  local rendered
  if dybatpho::is command chezmoi \
    && rendered="$(chezmoi execute-template --file "${source}" 2> /dev/null)"; then
    DYTOY_TUI_DETAIL["${index}"]="${rendered}"
  fi
  DYTOY_TUI_STATUS="Edited ${source##*/}; run chezmoi apply for dytoy to install from it"
}

#######################################
# @description Act on one key while a name is being searched for. Every
# printable key goes into the query, so the list keys of the normal mode are
# not available here; the arrows still move.
# @arg $1 string Event name
#######################################
function dytoy_tui::handle_search_key {
  local key
  dybatpho::expect_args key -- "$@"
  local -a matches=()
  dytoy_tui::search_matches matches
  local count="${#matches[@]}"
  case "${key}" in
    escape) DYTOY_TUI_MODE="normal" ;;
    enter)
      # Go to the match in its own tab, so picking carries on from there.
      if ((count > 0)); then
        local index="${matches[DYTOY_TUI_MATCH]}" position items_position
        local -a items=()
        for position in "${!DYTOY_METHODS[@]}"; do
          [[ "${DYTOY_METHODS[position]}" == "${DYTOY_TUI_METHOD[index]}" ]] && DYTOY_TUI_TAB="${position}"
        done
        dytoy_tui::tab_items items "${DYTOY_TUI_METHOD[index]}"
        for items_position in "${!items[@]}"; do
          ((items[items_position] == index)) && DYTOY_TUI_CURSOR["${DYTOY_TUI_METHOD[index]}"]="${items_position}"
        done
      fi
      DYTOY_TUI_MODE="normal"
      ;;
    up) ((count > 0)) && DYTOY_TUI_MATCH=$(((DYTOY_TUI_MATCH - 1 + count) % count)) ;;
    down) ((count > 0)) && DYTOY_TUI_MATCH=$(((DYTOY_TUI_MATCH + 1) % count)) ;;
    space) ((count > 0)) && dytoy_tui::toggle_pick "${matches[DYTOY_TUI_MATCH]}" ;;
    backspace)
      DYTOY_TUI_QUERY="${DYTOY_TUI_QUERY%?}"
      DYTOY_TUI_MATCH=0
      ;;
    char:*)
      DYTOY_TUI_QUERY+="${key#char:}"
      DYTOY_TUI_MATCH=0
      ;;
    resize) dybatpho::screen_size || true ;;
    eof) DYTOY_TUI_RUNNING=false ;;
    *) ;;
  esac
  return 0
}

#######################################
# @description Act on one key, in whichever phase the interface is in, and
# start installing when the key ended the pick phase.
# @arg $1 string Event name
#######################################
function dytoy_tui::handle_key {
  local key
  dybatpho::expect_args key -- "$@"
  if [[ "${DYTOY_TUI_PHASE}" != "pick" ]]; then
    dytoy_tui::handle_install_key "${key}"
    return 0
  fi
  dytoy_tui::handle_pick_key "${key}"
  [[ "${DYTOY_TUI_PHASE}" == "install" ]] && dytoy_tui::start_install
  return 0
}

#######################################
# @description Get the install phase ready: the log directory, the queue of
# picked tools, and `sudo`. A failed authentication goes back to picking with
# nothing installed.
# @noargs
#######################################
function dytoy_tui::start_install {
  # The logs are the interface's own, so they are written in a dry run too,
  # where `dybatpho::ensure_dir` would only say it creates them.
  mkdir -p -- "${DYTOY_TUI_LOG_DIR}"
  dytoy_tui::build_queue
  if ! dytoy_tui::prepare_sudo; then
    DYTOY_TUI_PHASE="pick"
    DYTOY_TUI_QUEUE=()
    DYTOY_TUI_STATUS="sudo authentication failed, nothing was installed"
  fi
  return 0
}

#######################################
# @description Act on one key in the install phase.
# @arg $1 string Event name
#######################################
function dytoy_tui::handle_install_key {
  local key
  dybatpho::expect_args key -- "$@"
  local count="${#DYTOY_TUI_QUEUE[@]}"
  if [[ "${DYTOY_TUI_MODE}" == "confirm" ]]; then
    # Only an explicit `y` stops anything: a dialog a stray key confirms reads
    # as a safeguard without being one.
    case "${key}" in
      char:y | char:Y)
        dytoy_tui::stop
        DYTOY_TUI_MODE="normal"
        ;;
      resize) dybatpho::screen_size || true ;;
      *) DYTOY_TUI_MODE="normal" ;;
    esac
    return 0
  fi

  case "${key}" in
    char:q | escape | eof)
      if [[ "${DYTOY_TUI_PHASE}" == "done" ]]; then
        DYTOY_TUI_RUNNING=false
      elif [[ "${key}" == "eof" ]]; then
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
# @description Point the log view, while following, at the first tool still
# running in install order, or at the last one started when none is.
# @noargs
#######################################
function dytoy_tui::follow {
  dybatpho::is true "${DYTOY_TUI_FOLLOW}" || return 0
  local position
  for ((position = 0; position < DYTOY_TUI_QUEUE_POS; position++)); do
    if [[ -n "${DYTOY_TUI_PIDS[${DYTOY_TUI_QUEUE[position]}]-}" ]]; then
      DYTOY_TUI_VIEW="${position}"
      return 0
    fi
  done
  position=$((DYTOY_TUI_QUEUE_POS - 1))
  ((position >= 0)) || position=0
  DYTOY_TUI_VIEW="${position}"
}

#######################################
# @description Set a variable to how many tools of a stage may run at once.
# A package manager holds a lock on its database, and `mise use -g` rewrites
# one global configuration file, so those two run one tool at a time, as do
# the shared dependencies, which may be of any method; the others take
# `DYTOY_TUI_JOBS`.
# @arg $1 string Name of the variable receiving the limit
# @arg $2 string Stage: a method, or `dependencies`
#######################################
function dytoy_tui::method_jobs_into {
  local __dytoy_tui_jobs_ref method
  dybatpho::expect_args __dytoy_tui_jobs_ref method -- "$@"
  local -n __dytoy_tui_jobs="${__dytoy_tui_jobs_ref}"
  case "${method}" in
    os | mise | dependencies) __dytoy_tui_jobs=1 ;;
    *) __dytoy_tui_jobs="${DYTOY_TUI_JOBS}" ;;
  esac
}

#######################################
# @description Return success when the next queued tool may start now. The
# stages still run in order -- the shared dependencies, then `os`, which
# installs what the others need, then the rest -- so a tool waits while one of
# an earlier stage is running, and otherwise while its stage has no free slot.
# @noargs
# @exitcode 0 The next tool may start
# @exitcode 1 It has to wait, or nothing is left to start
#######################################
function dytoy_tui::can_start {
  ((DYTOY_TUI_QUEUE_POS < ${#DYTOY_TUI_QUEUE[@]})) || return 1
  local next="${DYTOY_TUI_QUEUE[DYTOY_TUI_QUEUE_POS]}" index limit
  for index in "${!DYTOY_TUI_PIDS[@]}"; do
    [[ "${DYTOY_TUI_STAGE[index]}" == "${DYTOY_TUI_STAGE[next]}" ]] || return 1
  done
  dytoy_tui::method_jobs_into limit "${DYTOY_TUI_STAGE[next]}"
  ((${#DYTOY_TUI_PIDS[@]} < limit))
}

#######################################
# @description Start the next queued tool in a child of its own.
# @noargs
#######################################
function dytoy_tui::start_next {
  ((DYTOY_TUI_QUEUE_POS < ${#DYTOY_TUI_QUEUE[@]})) || return 0
  local index="${DYTOY_TUI_QUEUE[DYTOY_TUI_QUEUE_POS]}"
  DYTOY_TUI_QUEUE_POS=$((DYTOY_TUI_QUEUE_POS + 1))

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
  # The log is not a terminal, but its colours are drawn in the log pane, so
  # the tools that look for a terminal are told to colour anyway.
  local -a colour=()
  [[ -n "${NO_COLOR:-}" ]] || colour=(FORCE_COLOR=1 CLICOLOR_FORCE=1)
  set -m
  env PATH="${path}" "${colour[@]}" "${DYTOY_TUI_SELF}" "${args[@]}" >> "${log}" 2>&1 < /dev/null &
  DYTOY_TUI_PIDS["${index}"]=$!
  set +m
}

#######################################
# @description Collect every running tool that has ended, start as many queued
# tools as the slots allow, and end the install phase once nothing is left.
# @noargs
#######################################
function dytoy_tui::poll {
  [[ "${DYTOY_TUI_PHASE}" == "install" ]] || return 0
  local index pid status
  for index in "${!DYTOY_TUI_PIDS[@]}"; do
    pid="${DYTOY_TUI_PIDS[${index}]}"
    kill -0 "${pid}" 2> /dev/null && continue
    status=0
    wait "${pid}" 2> /dev/null || status=$?
    unset 'DYTOY_TUI_PIDS[${index}]'
    DYTOY_TUI_ELAPSED[index]=$((EPOCHSECONDS - DYTOY_TUI_STARTED[index]))
    if ((status == 0)); then
      DYTOY_TUI_STATE[index]="ok"
    else
      DYTOY_TUI_STATE[index]="failed"
      printf '\n[exit status %s]\n' "${status}" >> "${DYTOY_TUI_LOG[index]}"
    fi
  done
  while dytoy_tui::can_start; do
    dytoy_tui::start_next
  done
  if ((DYTOY_TUI_QUEUE_POS >= ${#DYTOY_TUI_QUEUE[@]} && ${#DYTOY_TUI_PIDS[@]} == 0)); then
    DYTOY_TUI_PHASE="done"
  fi
  dytoy_tui::follow
}

#######################################
# @description Terminate a running child and everything it started. A child
# stopped on a read from the terminal only acts on the signal once continued.
# @arg $1 number Process of the child
#######################################
function dytoy_tui::kill_child {
  local pid
  dybatpho::expect_args pid -- "$@"
  kill -TERM -- "-${pid}" 2> /dev/null || kill -TERM "${pid}" 2> /dev/null || true
  kill -CONT -- "-${pid}" 2> /dev/null || true
}

#######################################
# @description Stop every running tool and skip every tool not started yet.
# @noargs
#######################################
function dytoy_tui::stop {
  local index pid
  for index in "${!DYTOY_TUI_PIDS[@]}"; do
    pid="${DYTOY_TUI_PIDS[${index}]}"
    dytoy_tui::kill_child "${pid}"
    wait "${pid}" 2> /dev/null || true
    DYTOY_TUI_STATE[index]="failed"
    DYTOY_TUI_ELAPSED[index]=$((EPOCHSECONDS - DYTOY_TUI_STARTED[index]))
    printf '\n[stopped]\n' >> "${DYTOY_TUI_LOG[index]}"
  done
  DYTOY_TUI_PIDS=()
  local position
  for ((position = DYTOY_TUI_QUEUE_POS; position < ${#DYTOY_TUI_QUEUE[@]}; position++)); do
    DYTOY_TUI_STATE[DYTOY_TUI_QUEUE[position]]="skipped"
  done
  DYTOY_TUI_QUEUE_POS="${#DYTOY_TUI_QUEUE[@]}"
  DYTOY_TUI_PHASE="done"
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
    # dyshellint disable=BSG035 package managers need root, and the children cannot prompt
    sudo -v || status=$?
    dybatpho::screen_begin || return 1
    ((status == 0)) || return 1
    (
      while kill -0 "$$" 2> /dev/null; do
        # dyshellint disable=BSG035 refreshing the timestamp only, it never prompts
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
  local pid
  for pid in "${DYTOY_TUI_PIDS[@]}"; do
    dytoy_tui::kill_child "${pid}"
  done
  DYTOY_TUI_PIDS=()
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
# @env JOBS number Tools installed at once where their method allows, default `4`
# @set DYTOY_TUI_FAILED `true` when a tool failed or was stopped
# @exitcode 1 There is no terminal to take over
#######################################
function dytoy_tui::run {
  local self
  dybatpho::expect_args self -- "$@"
  DYTOY_TUI_SELF="${self}"
  DYTOY_TUI_JOBS="${JOBS:-4}"
  if [[ ! "${DYTOY_TUI_JOBS}" =~ ^[1-9][0-9]*$ ]]; then
    dybatpho::die "--jobs takes at least 1, got '${DYTOY_TUI_JOBS}'"
  fi
  local state_dir run_id yaml_file
  state_dir="$(dybatpho::xdg_state_dir dytoy)"
  run_id="$(date +%Y%m%d-%H%M%S)"
  yaml_file="$(dytoy::yaml_file)"
  DYTOY_TUI_LOG_DIR="$(dybatpho::path_join "${state_dir}" "logs" "${run_id}")"

  dybatpho::progress "Reading ${yaml_file}"
  dytoy_tui::load_tools
  dytoy_tui::theme

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
    elif ! dybatpho::screen_event key 0.1; then
      # The deadline keeps the spinner and the log moving while no key comes.
      dytoy_tui::poll
      continue
    fi
    dytoy_tui::handle_key "${key}"
    # Keys that arrived while the frame was drawing are all handled before the
    # next one is drawn, so a held arrow moves as fast as the key repeats and
    # stops as soon as it is released.
    while dybatpho::is true "${DYTOY_TUI_RUNNING}" && dybatpho::screen_pending; do
      dybatpho::screen_event key || break
      dytoy_tui::handle_key "${key}"
    done
    [[ "${DYTOY_TUI_PHASE}" == "pick" ]] || dytoy_tui::poll
  done

  dytoy_tui::screen_end
  dytoy_tui::cleanup
  dytoy_tui::summary
}
