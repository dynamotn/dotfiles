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

  local -a attrs=()
  mapfile -t attrs < <(dybatpho::split "${attributes}" ",")
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
# @arg $1 string Name of an array holding the attributes of that component
# @stdout Attribute prefixes in chezmoi order, each followed by `_`
#######################################
function __chezmoi_attrs_prefix {
  local -n __component_attrs="$1"
  local attr prefix=""
  for attr in "${CHEZMOI_ATTRS_ORDER[@]}"; do
    if dybatpho::array_contains __component_attrs "${attr}"; then
      prefix+="${attr}_"
    fi
  done
  printf '%s' "${prefix}"
}

#######################################
# @description Build the chezmoi source path of a target path
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
  local path_var target_path attributes
  dybatpho::expect_args path_var target_path attributes -- "$@"
  chezmoi_attrs::validate "${attributes}" || return 1

  local base_prefix relative_path
  # shellcheck disable=SC2088 # The `~` below is a literal the caller typed, not an expansion
  if [[ "${target_path}" == "${HOME}"/* ]]; then
    base_prefix="home/"
    relative_path="${target_path#"${HOME}"/}"
  elif [[ "${target_path}" == '~/'* ]]; then
    base_prefix="home/"
    relative_path="${target_path#'~/'}"
  elif [[ "${target_path}" == /* ]]; then
    base_prefix="root/"
    relative_path="${target_path#/}"
  else
    dybatpho::error "Target path ${target_path} must start with /, \$HOME or ~"
    return 1
  fi
  if [[ -z "${relative_path}" ]]; then
    dybatpho::error "Target path ${target_path} has no file name"
    return 1
  fi

  local -a components=() processed=() last_attrs=()
  IFS='/' read -r -a components <<< "${relative_path}"
  mapfile -t last_attrs < <(dybatpho::split "${attributes}" ",")
  local last_index=$((${#components[@]} - 1))

  local index component
  for index in "${!components[@]}"; do
    component="${components[${index}]}"
    local -a component_attrs=()
    # A dotted component is renamed and, by the convention above, made private.
    # Collecting `private` as an attribute instead of writing the prefix here is
    # what keeps `--attributes private` from producing `private_private_dot_`.
    if [[ "${component}" == .* ]]; then
      component="dot_${component#.}"
      component_attrs+=("private")
    fi
    if ((index == last_index)) && ((${#last_attrs[@]} > 0)); then
      component_attrs+=("${last_attrs[@]}")
    fi
    processed+=("$(__chezmoi_attrs_prefix component_attrs)${component}")
  done

  local IFS="/"
  printf -v "${path_var}" '%s' "${base_prefix}${processed[*]}"
}
