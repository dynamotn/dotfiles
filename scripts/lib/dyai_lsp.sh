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

#######################################
# @description Print the path of the owned-state file Task 4 also reads/writes
# @noargs
# @stdout Path to ${XDG_CACHE_HOME:-~/.cache}/dyai/lsp-owned.json
#######################################
function dyai_lsp::owned_file {
  # shellcheck disable=SC2312 # xdg_cache_dir only builds a path string, it cannot fail here
  dybatpho::path_join "$(dybatpho::xdg_cache_dir dyai)" "lsp-owned.json"
}

#######################################
# @description Read a value from the dyai-lsp owned-state file
# @arg $1 string Key to read
# @stdout The JSON value stored under that key, or `null` when absent
#######################################
function dyai_lsp::owned_get {
  local key file
  dybatpho::expect_args key -- "$@"
  file="$(dyai_lsp::owned_file)"
  if dybatpho::is file "${file}"; then
    jq -c --arg k "${key}" '.[$k] // null' "${file}"
  else
    printf 'null\n'
  fi
}

#######################################
# @description Store a JSON value under a key in the dyai-lsp owned-state file,
#   atomically, keeping every other key
# @arg $1 string Key to write
# @arg $2 string JSON value to store (any valid JSON, e.g. `"1.2.3"` or `{}`)
#######################################
function dyai_lsp::owned_set {
  local key value dir file tmp current
  dybatpho::expect_args key value -- "$@"
  dir="$(dybatpho::xdg_cache_dir dyai)"
  dybatpho::ensure_dir "${dir}" > /dev/null
  file="$(dyai_lsp::owned_file)"
  if dybatpho::is file "${file}"; then
    current="$(< "${file}")"
  else
    current="{}"
  fi
  dybatpho::create_temp tmp "json" "dyai-lsp-owned" "${dir}"
  jq --arg k "${key}" --argjson v "${value}" '.[$k] = $v' <<< "${current}" > "${tmp}" \
    && mv "${tmp}" "${file}"
}

#######################################
# @description Give each file extension in a manifest to the first server
#   (manifest order) that claims it
# @arg $1 string Path to the lsp.json manifest
# @stdout JSON `{<name>: {".ext": "lang", ...}}`; a server left with no
#   extension after the assignment is omitted
#######################################
function dyai_lsp::primary_extensions {
  local manifest
  dybatpho::expect_args manifest -- "$@"
  jq -c '
    reduce .servers[] as $s (
      {taken: {}, out: {}};
      ($s.extensions // {}) as $exts
      | reduce ($exts | keys_unsorted[]) as $ext (
          .;
          if .taken[$ext] then .
          else
            .taken[$ext] = true
            | .out[$s.name][$ext] = $exts[$ext]
          end
        )
    )
    | .out
  ' "${manifest}"
}

#######################################
# @description Build the launcher-wrapped argv for one manifest server
# @arg $1 string One server entry from the manifest, as JSON
# @stdout JSON array `["<HOME>/.local/bin/dyai-lsp-exec", name, "--", command, ...args]`
#######################################
function dyai_lsp::launch_argv {
  local server_json launcher
  dybatpho::expect_args server_json -- "$@"
  launcher="$(dybatpho::path_join "${HOME}" ".local" "bin" "dyai-lsp-exec")"
  jq -c --arg launcher "${launcher}" '
    [$launcher, .name, "--", .command] + (.args // [])
  ' <<< "${server_json}"
}

#######################################
# @description Build one manifest server's entry for the plugin's .lsp.json
# @arg $1 string One server entry from the manifest, as JSON
# @arg $2 string This server's extension map, as JSON (`{".ext": "lang"}`)
# @stdout JSON `{command, args, extensionToLanguage, maxRestarts,
#   settings?, initializationOptions?}`
#######################################
function __dyai_lsp_entry {
  local server_json ext_json argv settings init_opts
  dybatpho::expect_args server_json ext_json -- "$@"
  argv="$(dyai_lsp::launch_argv "${server_json}")"
  # shellcheck disable=SC2312 # a bad server entry yields {}, a safe no-op default
  settings="$(jq -c '.settings // {}' <<< "${server_json}")"
  # shellcheck disable=SC2312 # a bad server entry yields {}, a safe no-op default
  init_opts="$(jq -c '.init_options // {}' <<< "${server_json}")"
  jq -n \
    --argjson argv "${argv}" \
    --argjson ext "${ext_json}" \
    --argjson settings "${settings}" \
    --argjson init_opts "${init_opts}" '
    {
      command: $argv[0],
      args: $argv[1:],
      extensionToLanguage: $ext,
      maxRestarts: 3
    }
    + (if ($settings | length) > 0 then {settings: $settings} else {} end)
    + (if ($init_opts | length) > 0 then {initializationOptions: $init_opts} else {} end)
  '
}

#######################################
# @description Write the dyai-lsp marketplace and plugin for Claude, from the
#   lsp.json manifest, and register/update it with `claude` when needed
# @noargs
# @env XDG_CACHE_HOME string Base of the manifest and owned-state files
# @env XDG_DATA_HOME string Base of the marketplace directory
# @env HOME string Used to locate the launcher and `known_marketplaces.json`
#######################################
function dyai_lsp::setup_claude {
  local cache_dir manifest market_dir lsp_plugin_dir
  local market_meta_dir lsp_meta_dir lsp_json ext_map name server_json ext_json entry
  local data_dir
  cache_dir="$(dybatpho::xdg_cache_dir dyai)"
  manifest="$(dybatpho::path_join "${cache_dir}" "lsp.json")"
  data_dir="$(dybatpho::xdg_data_dir dyai)"
  market_dir="$(dybatpho::path_join "${data_dir}" "claude-marketplace")"
  lsp_plugin_dir="$(dybatpho::path_join "${market_dir}" "plugins" "dyai-lsp")"
  market_meta_dir="$(dybatpho::path_join "${market_dir}" ".claude-plugin")"
  lsp_meta_dir="$(dybatpho::path_join "${lsp_plugin_dir}" ".claude-plugin")"
  dybatpho::ensure_dir "${market_meta_dir}" > /dev/null
  dybatpho::ensure_dir "${lsp_meta_dir}" > /dev/null

  lsp_json="{}"
  if dybatpho::is file "${manifest}"; then
    ext_map="$(dyai_lsp::primary_extensions "${manifest}")"
    # shellcheck disable=SC2312 # a bad ext_map read yields no rows, a safe no-op loop
    while IFS= read -r name; do
      [[ -n "${name}" ]] || continue
      server_json="$(jq -c --arg n "${name}" '.servers[] | select(.name == $n)' "${manifest}")"
      # shellcheck disable=SC2312 # a name read from ext_map's own keys always has an entry
      ext_json="$(jq -c --arg n "${name}" '.[$n]' <<< "${ext_map}")"
      entry="$(__dyai_lsp_entry "${server_json}" "${ext_json}")"
      lsp_json="$(jq -c --arg n "${name}" --argjson e "${entry}" '.[$n] = $e' <<< "${lsp_json}")"
    done < <(jq -r 'keys[]' <<< "${ext_map}")
  fi

  local lsp_path market_json_path plugin_json_path tmp
  lsp_path="$(dybatpho::path_join "${lsp_plugin_dir}" ".lsp.json")"
  market_json_path="$(dybatpho::path_join "${market_meta_dir}" "marketplace.json")"
  plugin_json_path="$(dybatpho::path_join "${lsp_meta_dir}" "plugin.json")"
  dybatpho::create_temp tmp "json" "dyai-lsp" "${lsp_plugin_dir}"
  printf '%s' "${lsp_json}" > "${tmp}"
  mv "${tmp}" "${lsp_path}"

  local version marketplace_json plugin_json
  # shellcheck disable=SC2312 # a just-written file always hashes; sha256sum cannot fail here
  version="0.0.0-$(sha256sum "${lsp_path}" | cut -c1-12)"
  marketplace_json="$(
    jq -n '{name: "dyai-lsp", owner: {name: "dyai"},
      plugins: [{name: "dyai-lsp", source: "./plugins/dyai-lsp"}]}'
  )"
  printf '%s' "${marketplace_json}" > "${market_json_path}"
  plugin_json="$(jq -n --arg v "${version}" '{name: "dyai-lsp", version: $v}')"
  printf '%s' "${plugin_json}" > "${plugin_json_path}"

  local known_file version_json prev_version
  known_file="$(dybatpho::path_join "${HOME}" ".claude" "plugins" "known_marketplaces.json")"
  version_json="$(jq -n --arg v "${version}" '$v')"
  # shellcheck disable=SC2310 # a missing or non-matching file is a plain no
  if ! dyai::in_json_file "${known_file}" 'has("dyai-lsp")'; then
    dybatpho::info "Add dyai-lsp marketplace"
    claude plugin marketplace add "${market_dir}" || dybatpho::warn "Could not add dyai-lsp marketplace"
  else
    prev_version="$(dyai_lsp::owned_get claude_version)"
    if [[ "${prev_version}" != "${version_json}" ]]; then
      dybatpho::info "Update dyai-lsp marketplace and plugin to ${version}"
      claude plugin marketplace update dyai-lsp || dybatpho::warn "Could not update dyai-lsp marketplace"
      claude plugin update dyai-lsp@dyai-lsp || dybatpho::warn "Could not update dyai-lsp plugin"
    fi
  fi
  dyai_lsp::owned_set claude_version "${version_json}"
}
