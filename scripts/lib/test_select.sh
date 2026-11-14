#!/usr/bin/env bash
# @file test_select.sh
# @brief Pick the bats files that cover a set of changed paths
# @description The whole suite takes minutes, which is too long to run after
# every edit. A changed path selects the bats file named after it and every
# bats file that mentions it; a change to what all tests share, or to a file
# no test names, selects the whole suite. It errs towards running too much:
# the whole suite still runs once before a merge, and catches what a selection
# missed.

# Paths every test depends on: the runner, the helper, and the library both
# are built on.
__TEST_SELECT_ALL_RE='^scripts/(test\.sh|test/test_helper\.bash|lib/dybatpho|lib/test_select\.sh)$'
# Documentation, which no test needs to name: under `home/` a Markdown file is
# a template or an instruction file, and is tested.
__TEST_SELECT_PROSE_RE='^(docs/.*|[^/]+\.md)$'
# The attribute prefixes of a chezmoi source name, which a test never spells:
# `executable_dot_foo.sh.tmpl` is `.foo.sh` to it.
__TEST_SELECT_PREFIX_RE='^(create|dot|empty|encrypted|exact|executable|literal|modify|once|onchange'
__TEST_SELECT_PREFIX_RE+='|private|readonly|remove|run|symlink)_(.+)$'

#######################################
# @description Print the bats files covering the given changed paths
# shortcut: a library is matched by its file name only, so a change in one
# that another library sources does not select that other library's tests;
# follow the `source` lines when the full run before a merge keeps finding
# what this missed.
# @arg $1 string Root of the repository, whose bats files are in `scripts/test`
# @arg $@ string Changed paths, relative to that root
# @stdout One bats file per line, sorted, or the single line `--all` when a
# path all tests depend on changed, or one no test names: a test may still
# reach it through a glob. Nothing when only prose or deleted files changed
#######################################
function test_select::files {
  local root
  dybatpho::expect_args root -- "$@"
  shift

  local test_dir="${root}/scripts/test" path name file mentions found
  local -A picked=()
  for path in "$@"; do
    if [[ "${path}" =~ ${__TEST_SELECT_ALL_RE} ]]; then
      printf -- '--all\n'
      return 0
    fi
    # Neither a file nor a directory, yet there: an agent's sandbox masks the
    # files it may not read with a device, which is no change.
    if [[ -e "${root}/${path}" && ! -f "${root}/${path}" && ! -d "${root}/${path}" ]]; then
      continue
    fi
    name="${path%/}"
    name="${name##*/}"
    name="${name%.tmpl}"
    while [[ "${name}" =~ ${__TEST_SELECT_PREFIX_RE} ]]; do
      name="${BASH_REMATCH[2]}"
    done
    [[ -n "${name}" ]] || continue
    if [[ "${path}" == scripts/test/*.bats ]]; then
      file="${test_dir}/${name}"
    else
      file="${test_dir}/${name%.*}.bats"
    fi
    found=""
    if [[ -f "${file}" ]]; then
      picked["${file}"]=1
      found="true"
    fi
    # grep exits 1 when no file mentions the name, which is no failure here.
    mentions="$(grep -lF -- "${name}" "${test_dir}"/*.bats 2> /dev/null || true)"
    while IFS= read -r file; do
      [[ -n "${file}" ]] || continue
      picked["${file}"]=1
      found="true"
    done <<< "${mentions}"
    # A deleted file is left at that: the same sandbox shows the directories
    # it hides as deleted, and would turn every run into the whole suite.
    if [[ -z "${found}" && -e "${root}/${path}" && ! "${path}" =~ ${__TEST_SELECT_PROSE_RE} ]]; then
      printf -- '--all\n'
      return 0
    fi
  done
  ((${#picked[@]} == 0)) || printf '%s\n' "${!picked[@]}" | sort
}
