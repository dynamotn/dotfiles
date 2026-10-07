#!/usr/bin/env bash
# @file chezmoi_attrs.sh
# @brief Translate a target path into the source path chezmoi expects
# @description Encrypted files are written straight into the chezmoi source
# tree, so their source path has to be built by hand instead of by `chezmoi
# add`. The rules are chezmoi's own: attribute prefixes in a fixed order, then
# `dot_` for a leading dot. Every dotted component also gets `private_`, which
# is what the rest of `home/` already looks like; changing that default would
# move every file this library has already produced.

# @env CHEZMOI_ATTRS_ORDER array Attributes chezmoi accepts, in the order it writes their prefixes
CHEZMOI_ATTRS_ORDER=(create encrypted private readonly empty executable)

#######################################
# @description Check that every attribute of a list is one chezmoi knows
# @arg $1 string Attributes, separated by `,`
# @exitcode 0 Every attribute is known, or the list is empty
# @exitcode 1 An attribute is not in `CHEZMOI_ATTRS_ORDER`
#######################################
function chezmoi_attrs::validate {
  local attributes
  dybatpho::expect_args attributes -- "$@"

  local fields
  local -a attrs=()
  fields="$(dybatpho::split "${attributes}" ",")"
  mapfile -t attrs <<< "${fields}"
  local attr
  for attr in "${attrs[@]}"; do
    if [[ -n "${attr}" ]] && ! dybatpho::array_contains CHEZMOI_ATTRS_ORDER "${attr}"; then
      dybatpho::error "Unknown chezmoi attribute '${attr}', expected one of: ${CHEZMOI_ATTRS_ORDER[*]}"
      return 1
    fi
  done
}

#######################################
# @description Build the prefix of a single source path component
# @arg $1 string Name of the variable that receives the prefix
# @arg $2 string Name of an array holding the attributes of that component
# @set The variable named by `$1`: attribute prefixes in chezmoi order, each followed by `_`
#######################################
function __chezmoi_attrs_prefix_into {
  local __chezmoi_attrs_prefix_out __chezmoi_attrs_prefix_from
  dybatpho::expect_args __chezmoi_attrs_prefix_out __chezmoi_attrs_prefix_from -- "$@"
  dybatpho::expect_ref "${__chezmoi_attrs_prefix_out}"
  dybatpho::expect_ref "${__chezmoi_attrs_prefix_from}"
  local -n __chezmoi_attrs_prefix_ref="${__chezmoi_attrs_prefix_out}"
  local -n __chezmoi_attrs_prefix_attrs="${__chezmoi_attrs_prefix_from}"
  local __chezmoi_attrs_prefix_attr __chezmoi_attrs_prefix_text=""
  for __chezmoi_attrs_prefix_attr in "${CHEZMOI_ATTRS_ORDER[@]}"; do
    if dybatpho::array_contains __chezmoi_attrs_prefix_attrs "${__chezmoi_attrs_prefix_attr}"; then
      __chezmoi_attrs_prefix_text+="${__chezmoi_attrs_prefix_attr}_"
    fi
  done
  __chezmoi_attrs_prefix_ref="${__chezmoi_attrs_prefix_text}"
}

#######################################
# @description Build the chezmoi source path of a target path
#   Every working variable carries the `__chezmoi_attrs_sp_` prefix: the path is
#   written through a name the caller chose, and a plain local of the same name
#   would receive it instead of the caller's variable.
# @arg $1 string Variable name that receives the source path
# @arg $2 string Target path, must start with `/`, `$HOME` or `~`
# @arg $3 string Attributes of the last component, separated by `,`
# @exitcode 0 The source path is written to the variable named by `$1`
# @exitcode 1 The target path is not absolute, or an attribute is unknown
# @example
#   local source_path
#   chezmoi_attrs::source_path source_path "${HOME}/.config/foo" "create,encrypted"
#   # home/private_dot_config/create_encrypted_private_dot_foo
#######################################
function chezmoi_attrs::source_path {
  local __chezmoi_attrs_sp_var __chezmoi_attrs_sp_target __chezmoi_attrs_sp_attributes
  dybatpho::expect_args __chezmoi_attrs_sp_var __chezmoi_attrs_sp_target __chezmoi_attrs_sp_attributes -- "$@"
  chezmoi_attrs::validate "${__chezmoi_attrs_sp_attributes}" || return 1

  local __chezmoi_attrs_sp_base __chezmoi_attrs_sp_relative
  # shellcheck disable=SC2088 # The `~` below is a literal the caller typed, not an expansion
  if [[ "${__chezmoi_attrs_sp_target}" == "${HOME}"/* ]]; then
    __chezmoi_attrs_sp_base="home/"
    __chezmoi_attrs_sp_relative="${__chezmoi_attrs_sp_target#"${HOME}"/}"
  elif [[ "${__chezmoi_attrs_sp_target}" == '~/'* ]]; then
    __chezmoi_attrs_sp_base="home/"
    __chezmoi_attrs_sp_relative="${__chezmoi_attrs_sp_target#'~/'}"
  elif [[ "${__chezmoi_attrs_sp_target}" == /* ]]; then
    __chezmoi_attrs_sp_base="root/"
    __chezmoi_attrs_sp_relative="${__chezmoi_attrs_sp_target#/}"
  else
    dybatpho::error "Target path ${__chezmoi_attrs_sp_target} must start with /, \$HOME or ~"
    return 1
  fi
  if [[ -z "${__chezmoi_attrs_sp_relative}" ]]; then
    dybatpho::error "Target path ${__chezmoi_attrs_sp_target} has no file name"
    return 1
  fi

  local __chezmoi_attrs_sp_fields
  local -a __chezmoi_attrs_sp_components=() __chezmoi_attrs_sp_last_attrs=()
  IFS='/' read -r -a __chezmoi_attrs_sp_components <<< "${__chezmoi_attrs_sp_relative}"
  __chezmoi_attrs_sp_fields="$(dybatpho::split "${__chezmoi_attrs_sp_attributes}" ",")"
  mapfile -t __chezmoi_attrs_sp_last_attrs <<< "${__chezmoi_attrs_sp_fields}"
  local __chezmoi_attrs_sp_last=$((${#__chezmoi_attrs_sp_components[@]} - 1))

  local __chezmoi_attrs_sp_index __chezmoi_attrs_sp_component __chezmoi_attrs_sp_prefix
  local __chezmoi_attrs_sp_joined=""
  for __chezmoi_attrs_sp_index in "${!__chezmoi_attrs_sp_components[@]}"; do
    __chezmoi_attrs_sp_component="${__chezmoi_attrs_sp_components[${__chezmoi_attrs_sp_index}]}"
    local -a __chezmoi_attrs_sp_component_attrs=()
    # A dotted component is renamed and, by the convention above, made private.
    # Collecting `private` as an attribute instead of writing the prefix here is
    # what keeps `--attributes private` from producing `private_private_dot_`.
    if [[ "${__chezmoi_attrs_sp_component}" == .* ]]; then
      __chezmoi_attrs_sp_component="dot_${__chezmoi_attrs_sp_component#.}"
      __chezmoi_attrs_sp_component_attrs+=("private")
    fi
    if ((__chezmoi_attrs_sp_index == __chezmoi_attrs_sp_last)) \
      && ((${#__chezmoi_attrs_sp_last_attrs[@]} > 0)); then
      __chezmoi_attrs_sp_component_attrs+=("${__chezmoi_attrs_sp_last_attrs[@]}")
    fi
    __chezmoi_attrs_prefix_into __chezmoi_attrs_sp_prefix __chezmoi_attrs_sp_component_attrs
    [[ -z "${__chezmoi_attrs_sp_joined}" ]] || __chezmoi_attrs_sp_joined+="/"
    __chezmoi_attrs_sp_joined+="${__chezmoi_attrs_sp_prefix}${__chezmoi_attrs_sp_component}"
  done

  printf -v "${__chezmoi_attrs_sp_var}" '%s' "${__chezmoi_attrs_sp_base}${__chezmoi_attrs_sp_joined}"
}
