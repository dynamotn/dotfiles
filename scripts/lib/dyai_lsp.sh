# @file dyai_lsp.sh
# @brief Export Neovim's configured language servers into a dyai manifest
# @description Runs the Lua exporter (`dyai_lsp_export.lua`) headless against
# the Neovim config already on this machine, and writes the resulting
# manifest atomically to the dyai cache, for every agent writer to read.
# Sourced (not executed); the caller sources dybatpho first and owns strict
# mode. See docs/superpowers/specs/2026-10-25-dyai-lsp-design.md §1.
# shellcheck shell=bash

#######################################
# @description Read global.lsp.exclude from the dyai config as a comma-separated list
# @noargs
# @stdout The excluded server names, comma-separated (empty when none/missing)
#######################################
function dyai_lsp::exclude_csv {
  # shellcheck disable=SC2312 # a bad config read yields no rows, a safe empty list
  dyai::config_json '.global.lsp.exclude // []' | jq -r 'join(",")'
}

#######################################
# @description Export Neovim's language servers into ${XDG_CACHE_HOME:-~/.cache}/dyai/lsp.json
# @noargs
# @env DYAI_NVIM string [default: nvim] The nvim binary to run
# @env DYAI_NVIM_CONFIG string [default: ${XDG_CONFIG_HOME:-~/.config}/nvim] Neovim config directory
# @env DYAI_LSPCONFIG_DIR string [default: ${XDG_DATA_HOME:-~/.local/share}/nvim/lazy/nvim-lspconfig]
# @env DYAI_MASON_BIN string [default: ${XDG_DATA_HOME:-~/.local/share}/nvim/mason/bin]
# @env CONFIG_FILE string The dyai config read for global.lsp.exclude
# @exitcode 1 nvim is missing or the export failed; the old manifest, if any, is left in place
#######################################
function dyai_lsp::export {
  local nvim_bin nvim_cfg lspconfig_dir mason_bin exclude_csv
  nvim_bin="${DYAI_NVIM:-nvim}"
  nvim_cfg="${DYAI_NVIM_CONFIG:-$(dybatpho::xdg_config_dir nvim)}"
  # shellcheck disable=SC2312 # xdg_data_dir only builds a path string, it cannot fail here
  lspconfig_dir="${DYAI_LSPCONFIG_DIR:-$(dybatpho::path_join "$(dybatpho::xdg_data_dir nvim)" "lazy" "nvim-lspconfig")}"
  # shellcheck disable=SC2312 # xdg_data_dir only builds a path string, it cannot fail here
  mason_bin="${DYAI_MASON_BIN:-$(dybatpho::path_join "$(dybatpho::xdg_data_dir nvim)" "mason" "bin")}"
  if ! dybatpho::is command "${nvim_bin}"; then
    dybatpho::warn "nvim (${nvim_bin}) is not installed, skip exporting language servers"
    return 1
  fi
  exclude_csv="$(dyai_lsp::exclude_csv)"
  local exporter cache_dir manifest tmp
  exporter="$(dybatpho::path_join "${BASH_SOURCE[0]%/*}" "dyai_lsp_export.lua")"
  cache_dir="$(dybatpho::xdg_cache_dir dyai)"
  manifest="$(dybatpho::path_join "${cache_dir}" "lsp.json")"
  dybatpho::ensure_dir "${cache_dir}" > /dev/null
  dybatpho::create_temp tmp "json" "dyai-lsp" "${cache_dir}"
  if "${nvim_bin}" --clean --headless -l "${exporter}" \
    "${nvim_cfg}" "${lspconfig_dir}" "${mason_bin}" "${tmp}" "${exclude_csv}"; then
    mv "${tmp}" "${manifest}"
    dybatpho::info "Exported language servers to ${manifest}"
  else
    rm -f "${tmp}"
    dybatpho::warn "Could not export language servers, keeping the previous manifest"
    return 1
  fi
}
