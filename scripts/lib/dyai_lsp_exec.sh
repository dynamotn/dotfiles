# @file dyai_lsp_exec.sh
# @brief Trust-gated launcher wrapping every agent-facing language-server command
# @description Every agent config points its LSP `command` at
# `dyai-lsp-exec <name> -- <real command> [args...]` instead of the server
# binary directly, so no language server ever starts inside a directory
# Neovim holds as untrusted (`.worktrees/dyreview-*`, released only by
# `:DyReview trust` inside that Neovim session). When the current directory
# is not held, `exec`s straight into the real command: stdio passes through
# untouched, since it carries the LSP protocol, and there is no extra
# process. Sourced (not executed); the caller sources dybatpho first and
# owns strict mode. See docs/superpowers/specs/2026-10-25-dyai-lsp-design.md
# §1b.
# shellcheck shell=bash

# The exporter (dyai_lsp.sh) writes this same pattern into the manifest's
# `untrusted_regexes` when it can read Neovim's `plugin/review.lua`. This is
# only the fail-closed fallback for a missing or unreadable manifest.
DYAI_LSP_EXEC_DEFAULT_REGEX='^(.*/\.worktrees/dyreview-[^/]+)(/|$)'

#######################################
# @description Whether a directory is held untrusted by Neovim
# @arg $1 string Directory to check
# @arg $2 string Path of the dyai LSP manifest (untrusted_regexes array)
# @exitcode 0 The directory's realpath matches a hold pattern
# @exitcode 1 It matches none
#######################################
function dyai_lsp_exec::held {
  local dir manifest real re
  dybatpho::expect_args dir manifest -- "$@"
  real="$(realpath -m "${dir}")"
  local -a regexes=()
  # A missing or invalid manifest, or one with no regexes, yields no rows
  # here; the fallback below then fails closed on review worktrees.
  # shellcheck disable=SC2312 # a bad manifest yields no rows, caught by the empty-array fallback
  mapfile -t regexes < <(jq -r '.untrusted_regexes[]?' "${manifest}" 2> /dev/null)
  ((${#regexes[@]} > 0)) || regexes=("${DYAI_LSP_EXEC_DEFAULT_REGEX}")
  for re in ${regexes[@]+"${regexes[@]}"}; do
    [[ "${real}" =~ ${re} ]] && return 0
  done
  return 1
}

#######################################
# @description Run a language server, refusing inside a directory Neovim holds untrusted
# @arg $1 string Server name, used only in the refusal message
# @arg $2 string Literal `--`
# @arg $3.. string The real command and its arguments
# @env DYAI_LSP_MANIFEST string [default: ${XDG_CACHE_HOME:-~/.cache}/dyai/lsp.json] Manifest path
# @stderr One line naming the hold, when held
# @exitcode 3 The current directory is held untrusted; the server was not started
#######################################
function dyai_lsp_exec::main {
  local name separator manifest cache_dir dir
  (($# >= 2)) || dybatpho::die "Usage: dyai-lsp-exec <name> -- <cmd> [args...]"
  dybatpho::expect_args name separator -- "$@"
  shift 2
  [[ "${separator}" == "--" ]] || dybatpho::die "Usage: dyai-lsp-exec <name> -- <cmd> [args...]"
  (($# >= 1)) || dybatpho::die "Usage: dyai-lsp-exec <name> -- <cmd> [args...]"
  if [[ -z "${DYAI_LSP_MANIFEST-}" ]]; then
    cache_dir="$(dybatpho::xdg_cache_dir dyai)"
    manifest="$(dybatpho::path_join "${cache_dir}" "lsp.json")"
  else
    manifest="${DYAI_LSP_MANIFEST-}"
  fi
  dir="${PWD}"
  if dyai_lsp_exec::held "${dir}" "${manifest}"; then
    echo "dyai-lsp-exec: ${name} not started: ${dir} is held untrusted by Neovim (:DyReview trust)" >&2
    return 3
  fi
  exec "$@"
}
