#!/usr/bin/env bash
# @file kernel.sh
# @brief Library `kernel` to configure a hand-built kernel from fragments
# @description Library `kernel` to turn a base defconfig and tuning fragments
# into a kernel `.config`, and to prove that Kconfig kept every option the
# fragments ask for. `make olddefconfig` drops an option silently when one of
# its dependencies is missing; checking afterwards turns that into an error
# instead of a kernel built without it.
# shellcheck disable=2154
dybatpho::load privilege

#######################################
# @description Run a command that writes into a kernel source tree, elevated
# only when the current user cannot write there: /usr/src/linux is root-owned,
# a tree in the user's home is not and must stay user-owned.
# @arg $1 string Kernel source directory
# @arg $2 string Literal `--` separating the directory from the command
# @arg $@ string Command and arguments to run
#######################################
function kernel::run_in_tree {
  local __kernel_run_in_tree_dir __kernel_run_in_tree_separator
  dybatpho::expect_args __kernel_run_in_tree_dir __kernel_run_in_tree_separator -- "$@"
  shift 2
  [[ "${__kernel_run_in_tree_separator}" == "--" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected: dir -- command"
  if [[ -w "${__kernel_run_in_tree_dir}" ]]; then
    "$@"
  else
    dybatpho::privilege_run -- "$@"
  fi
}

#######################################
# @description Check that a directory is a full kernel source tree that can
# be built. gentoo-kernel leaves a trimmed tree under /usr/src, with Kconfig
# and Makefiles but no C sources, for out-of-tree modules only: configuring it
# would only overwrite the .config those modules are built against.
# @arg $1 string Kernel source directory
# @exitcode 0 The tree can be configured and built
# @exitcode 1 It cannot; the reason is printed on stderr
#######################################
function kernel::check_tree {
  local source_dir
  dybatpho::expect_args source_dir -- "$@"
  local marker main
  marker="$(dybatpho::path_join "${source_dir}" "dist-kernel")"
  main="$(dybatpho::path_join "${source_dir}" "init" "main.c")"
  if [[ -e "${marker}" ]]; then
    printf '%s is the module tree of a gentoo-kernel dist kernel\n' "${source_dir}" >&2
    return 1
  fi
  if [[ ! -f "${main}" ]]; then
    printf '%s holds no kernel sources\n' "${source_dir}" >&2
    return 1
  fi
}

#######################################
# @description Print the value of one option in a kernel config
# @arg $1 string Path of the kernel config
# @arg $2 string Option name, without the `CONFIG_` prefix
# @stdout Value as written in the config (`y`, `m`, a number or a quoted
# string), or `n` when the option is unset or absent
#######################################
function kernel::config_value {
  local config symbol
  dybatpho::expect_args config symbol -- "$@"
  local line
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" == "CONFIG_${symbol}="* ]]; then
      printf '%s\n' "${line#*=}"
      return
    fi
  done < "${config}"
  printf 'n\n'
}

#######################################
# @description Check that a kernel config honours every option of a fragment.
# A module asked for (`m`) is also satisfied when built in (`y`), since the
# feature is there either way; anything else must match exactly.
# @arg $1 string Path of the kernel config
# @arg $2 string Path of the fragment
# @stdout One line per option that does not match, as `NAME: want X, got Y`
# @exitcode 0 Every option matches
# @exitcode 1 At least one option does not match
#######################################
function kernel::verify_config {
  local config fragment
  dybatpho::expect_args config fragment -- "$@"
  local -A actual=()
  local line
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" == CONFIG_*=* ]] || continue
    line="${line#CONFIG_}"
    actual["${line%%=*}"]="${line#*=}"
  done < "${config}"

  local symbol want got failed=0
  local set_re='^CONFIG_([A-Za-z0-9_]+)=(.*)$'
  local unset_re='^# CONFIG_([A-Za-z0-9_]+) is not set$'
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" =~ ${set_re} ]]; then
      symbol="${BASH_REMATCH[1]}"
      want="${BASH_REMATCH[2]}"
    elif [[ "${line}" =~ ${unset_re} ]]; then
      symbol="${BASH_REMATCH[1]}"
      want="n"
    else
      continue
    fi
    got="${actual[${symbol}]:-n}"
    if [[ "${got}" == "${want}" ]] || [[ "${want}" == "m" && "${got}" == "y" ]]; then
      continue
    fi
    printf '%s: want %s, got %s\n' "${symbol}" "${want}" "${got}"
    failed=1
  done < "${fragment}"
  return "${failed}"
}

#######################################
# @description Write the `.config` of a kernel source tree from a base
# defconfig and fragments, resolved with `make olddefconfig`. The tree is
# usually root-owned, so the writes go through `kernel::run_in_tree`.
# @arg $1 string Kernel source directory
# @arg $2 string Path of the base defconfig
# @arg $@ string Paths of the fragments, applied in order
#######################################
function kernel::merge_config {
  local __kernel_merge_config_dir __kernel_merge_config_base
  dybatpho::expect_args __kernel_merge_config_dir __kernel_merge_config_base -- "$@"
  shift 2
  local __kernel_merge_config_script __kernel_merge_config_target
  __kernel_merge_config_script="$(dybatpho::path_join \
    "${__kernel_merge_config_dir}" "scripts" "kconfig" "merge_config.sh")"
  __kernel_merge_config_target="$(dybatpho::path_join "${__kernel_merge_config_dir}" ".config")"
  dybatpho::is file "${__kernel_merge_config_script}" \
    || dybatpho::die "${__kernel_merge_config_dir} is not a kernel source tree"
  dybatpho::is file "${__kernel_merge_config_base}" \
    || dybatpho::die "Base config not found: ${__kernel_merge_config_base}"
  local __kernel_merge_config_fragment
  for __kernel_merge_config_fragment in "$@"; do
    dybatpho::is file "${__kernel_merge_config_fragment}" \
      || dybatpho::die "Fragment not found: ${__kernel_merge_config_fragment}"
  done

  dybatpho::progress "Merging ${__kernel_merge_config_base} and $# fragment(s) into ${__kernel_merge_config_target}"
  kernel::run_in_tree "${__kernel_merge_config_dir}" -- \
    cp "${__kernel_merge_config_base}" "${__kernel_merge_config_target}"
  if (($# > 0)); then
    # merge_config.sh works on the current directory's tree.
    (
      cd "${__kernel_merge_config_dir}" || exit 1
      kernel::run_in_tree "${__kernel_merge_config_dir}" -- \
        "${__kernel_merge_config_script}" -m .config "$@"
    )
  fi
  kernel::run_in_tree "${__kernel_merge_config_dir}" -- \
    make -C "${__kernel_merge_config_dir}" olddefconfig
}

#######################################
# @description Re-resolve a base defconfig against the Kconfig of another
# kernel version, without any fragment: options that were renamed, became
# built-in or disappeared drop out, and every hardware choice stays.
# @arg $1 string Kernel source directory of the new version
# @arg $2 string Path of the current base defconfig
# @arg $3 string Destination path of the refreshed base defconfig
#######################################
function kernel::refresh_base {
  local source_dir base destination
  dybatpho::expect_args source_dir base destination -- "$@"
  kernel::merge_config "${source_dir}" "${base}"
  kernel::save_defconfig "${source_dir}" "${destination}"
}

#######################################
# @description Save the `.config` of a kernel source tree as a minimal
# defconfig, to refresh a base config after `make menuconfig`
# @arg $1 string Kernel source directory
# @arg $2 string Destination path of the defconfig
#######################################
function kernel::save_defconfig {
  local source_dir destination
  dybatpho::expect_args source_dir destination -- "$@"
  local defconfig
  defconfig="$(dybatpho::path_join "${source_dir}" "defconfig")"
  kernel::run_in_tree "${source_dir}" -- make -C "${source_dir}" savedefconfig
  cp "${defconfig}" "${destination}"
}
