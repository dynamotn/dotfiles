# @file dyai_lsp.sh
# @brief Export Neovim's configured language servers into a dyai manifest
# @description Runs the Lua exporter (`dyai_lsp_export.lua`) headless against
# the Neovim config already on this machine, and writes the resulting
# manifest atomically to the dyai cache, for every agent writer to read.
# Sourced (not executed); the caller sources dybatpho first and owns strict
# mode. See docs/superpowers/specs/2026-10-25-dyai-lsp-design.md §1.
# shellcheck shell=bash

# Neovim server name -> serena ls_specific_settings language key, for the
# rows the Task 0 spike confirmed `ls_base_cmd` is honored by (Ruling 5).
# gopls/lua_ls (Ruling 6) and terraformls/dartls (Ruling 7) are handled
# elsewhere / not at all; they are deliberately absent from this map.
declare -gA DYAI_LSP_SERENA_LANG=(
  [pyright]=python
  [rust_analyzer]=rust
  [clangd]=cpp
  [bashls]=bash
  [yamlls]=yaml
  [taplo]=toml
  [marksman]=markdown
  [intelephense]=php
)

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
# @description Map a Neovim server name to the Hermes built-in id it matches,
#   when one exists. Confirmed against
#   ~/.hermes/hermes-agent/agent/lsp/servers.py: lua_ls, bashls and yamlls
#   have no matching built-in id there (the real ids are lua-language-server,
#   bash-language-server and yaml-language-server), so those fall through to
#   the Neovim name unchanged.
# @arg $1 string Neovim server name
# @stdout The Hermes built-in id, or the Neovim name when there is no match
#######################################
function __dyai_lsp_hermes_id {
  local name
  dybatpho::expect_args name -- "$@"
  case "${name}" in
    pyright) printf 'pyright\n' ;;
    gopls) printf 'gopls\n' ;;
    rust_analyzer) printf 'rust-analyzer\n' ;;
    clangd) printf 'clangd\n' ;;
    *) printf '%s\n' "${name}" ;;
  esac
}

#######################################
# @description Merge a map of entries into a top-level object key of a JSON
#   file, pruning stale dyai-owned keys first, idempotently (jq -S compare).
#   A key that already exists in the block and is not in the caller's
#   owned-state list is left untouched (a user's own hand-written entry),
#   with one warning, and is left out of the printed owned-key list.
# @arg $1 string Agent name, for the warning message only (e.g. copilot)
# @arg $2 string Path of the JSON config file (created as {} when missing)
# @arg $3 string Top-level key that holds the entries (e.g. lspServers, lsp)
# @arg $4 string Entries to merge in, as a JSON object {name: entry}
# @arg $5 string JSON array of keys to delete from the block before merging
# @arg $6 string JSON array of keys dyai owned before this run
# @stdout JSON array of the keys dyai actually wrote (excludes any left
#   untouched because a foreign entry already claimed that name)
#######################################
function __dyai_lsp_write_json_block {
  local agent file block_key entries_json prune_json owned_before_json
  dybatpho::expect_args agent file block_key entries_json prune_json owned_before_json -- "$@"
  local dir current_norm current_block collided filtered_entries applied_names key
  local new_content new_norm tmp
  dir="$(dirname "${file}")"
  dybatpho::ensure_dir "${dir}" > /dev/null
  dybatpho::is file "${file}" || printf '{}\n' > "${file}"
  # shellcheck disable=SC2312 # a malformed file falls back to {}, forcing a rewrite attempt
  current_norm="$(jq -S . "${file}" 2> /dev/null || printf '{}')"
  # shellcheck disable=SC2312 # a malformed file falls back to {}, a safe no-op default
  current_block="$(jq -c --arg b "${block_key}" '.[$b] // {}' "${file}" 2> /dev/null || printf '{}')"
  collided="$(
    jq -cn --argjson entries "${entries_json}" --argjson owned "${owned_before_json}" --argjson cur "${current_block}" '
      [ ($entries | keys_unsorted[]) as $k
        | select(($cur | has($k)) and (($owned // []) | index($k) | not))
        | $k
      ]
    '
  )"
  # shellcheck disable=SC2312 # a malformed collided list yields no rows, a safe no-op loop
  while IFS= read -r key; do
    [[ -n "${key}" ]] || continue
    dybatpho::warn "Leaving ${agent}'s hand-written ${block_key}.${key} untouched in ${file}: dyai does not own it"
  done < <(jq -r '.[]' <<< "${collided}")
  filtered_entries="$(
    jq -c --argjson collided "${collided}" 'with_entries(select(.key as $k | ($collided | index($k)) | not))' \
      <<< "${entries_json}"
  )"
  applied_names="$(jq -c 'keys' <<< "${filtered_entries}")"
  new_content="$(
    jq --arg b "${block_key}" --argjson entries "${filtered_entries}" --argjson prune "${prune_json}" '
      .[$b] = (.[$b] // {})
      | reduce $prune[] as $k (.; .[$b] |= del(.[$k]))
      | reduce ($entries | keys_unsorted[]) as $k (.; .[$b][$k] = $entries[$k])
    ' "${file}" 2> /dev/null
  )"
  if [[ -z "${new_content}" ]]; then
    dybatpho::warn "Could not read ${file} as JSON, skip dyai-lsp update"
    printf '[]\n'
    return 1
  fi
  new_norm="$(jq -S . <<< "${new_content}")"
  if [[ "${current_norm}" == "${new_norm}" ]]; then
    dybatpho::debug "dyai-lsp entries already up to date in ${file}"
    printf '%s\n' "${applied_names}"
    return 0
  fi
  dybatpho::create_temp tmp "json" "dyai-lsp" "${dir}"
  printf '%s' "${new_content}" > "${tmp}" && mv "${tmp}" "${file}"
  dybatpho::info "Updated dyai-lsp entries in ${file}"
  printf '%s\n' "${applied_names}"
}

#######################################
# @description Merge a map of entries into Hermes' `.lsp.servers`, pruning
#   stale dyai-owned keys first, idempotently (jq -S compare on that subtree).
#   A key that already exists there and is not in the caller's owned-state
#   list is left untouched (a user's own hand-written entry), with one
#   warning, and is left out of the printed owned-key list.
# @arg $1 string Agent name, for the warning message only (hermes)
# @arg $2 string Path of the YAML config file (created empty when missing)
# @arg $3 string Entries to merge in, as a JSON object {id: entry}
# @arg $4 string JSON array of ids to delete from `.lsp.servers` before merging
# @arg $5 string JSON array of ids dyai owned before this run
# @stdout JSON array of the ids dyai actually wrote (excludes any left
#   untouched because a foreign entry already claimed that id)
#######################################
function __dyai_lsp_write_yaml_block {
  local agent file entries_json prune_json owned_before_json
  dybatpho::expect_args agent file entries_json prune_json owned_before_json -- "$@"
  local dir current_json cur_norm collided filtered_entries applied_names key
  local new_servers new_norm
  dir="$(dirname "${file}")"
  dybatpho::ensure_dir "${dir}" > /dev/null
  dybatpho::is file "${file}" || : > "${file}"
  # shellcheck disable=SC2312 # a malformed file or missing path yields {}, a safe no-op default
  current_json="$(yq -o=json '.lsp.servers // {}' "${file}" 2> /dev/null || printf '{}')"
  cur_norm="$(jq -cS . <<< "${current_json}" 2> /dev/null || printf '{}')"
  collided="$(
    jq -cn --argjson entries "${entries_json}" --argjson owned "${owned_before_json}" --argjson cur "${current_json}" '
      [ ($entries | keys_unsorted[]) as $k
        | select(($cur | has($k)) and (($owned // []) | index($k) | not))
        | $k
      ]
    '
  )"
  # shellcheck disable=SC2312 # a malformed collided list yields no rows, a safe no-op loop
  while IFS= read -r key; do
    [[ -n "${key}" ]] || continue
    dybatpho::warn "Leaving ${agent}'s hand-written lsp.servers.${key} untouched in ${file}: dyai does not own it"
  done < <(jq -r '.[]' <<< "${collided}")
  filtered_entries="$(
    jq -c --argjson collided "${collided}" 'with_entries(select(.key as $k | ($collided | index($k)) | not))' \
      <<< "${entries_json}"
  )"
  applied_names="$(jq -c 'keys' <<< "${filtered_entries}")"
  new_servers="$(
    jq --argjson entries "${filtered_entries}" --argjson prune "${prune_json}" '
      reduce $prune[] as $k (.; del(.[$k]))
      | reduce ($entries | keys_unsorted[]) as $k (.; .[$k] = $entries[$k])
    ' <<< "${current_json}"
  )"
  new_norm="$(jq -cS . <<< "${new_servers}")"
  if [[ "${cur_norm}" == "${new_norm}" ]]; then
    dybatpho::debug "dyai-lsp entries already up to date in ${file}"
    printf '%s\n' "${applied_names}"
    return 0
  fi
  if E="${new_servers}" yq -i '.lsp.servers = (strenv(E) | fromjson)' "${file}"; then
    dybatpho::info "Updated dyai-lsp entries in ${file}"
  else
    dybatpho::warn "Could not update dyai-lsp entries in ${file}"
  fi
  printf '%s\n' "${applied_names}"
}

#######################################
# @description Write the Neovim language servers' primary extensions into
#   Copilot's `lsp-config.json`, launcher-wrapped, pruning servers dyai wrote
#   before that are no longer in the manifest. Runs only if `copilot` is on
#   PATH; leaves the file untouched (with a warning) when the manifest is
#   missing or invalid.
# @noargs
# @env COPILOT_HOME string [default: ~/.copilot] Base directory of Copilot's config
# @env XDG_CACHE_HOME string Base of the manifest and owned-state files
#######################################
function dyai_lsp::setup_copilot {
  dybatpho::is command copilot || return 0
  local manifest
  # shellcheck disable=SC2312 # xdg_cache_dir only builds a path string, it cannot fail here
  manifest="$(dybatpho::path_join "$(dybatpho::xdg_cache_dir dyai)" "lsp.json")"
  if ! dybatpho::is file "${manifest}"; then
    dybatpho::warn "No dyai-lsp manifest at ${manifest}, skip Copilot"
    return 1
  fi
  local ext_map
  # shellcheck disable=SC2312 # a malformed manifest yields no output, caught below
  ext_map="$(dyai_lsp::primary_extensions "${manifest}" 2> /dev/null)"
  if ! jq -e . <<< "${ext_map}" &> /dev/null; then
    dybatpho::warn "Invalid dyai-lsp manifest ${manifest}, skip Copilot"
    return 1
  fi
  local entries name server_json ext_json argv entry
  entries="{}"
  # shellcheck disable=SC2312 # a malformed ext_map yields no keys, a safe no-op loop
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    server_json="$(jq -c --arg n "${name}" '.servers[] | select(.name == $n)' "${manifest}")"
    # shellcheck disable=SC2312 # a name read from ext_map's own keys always has an entry
    ext_json="$(jq -c --arg n "${name}" '.[$n]' <<< "${ext_map}")"
    argv="$(dyai_lsp::launch_argv "${server_json}")"
    entry="$(
      jq -n --argjson argv "${argv}" --argjson ext "${ext_json}" '
        {command: $argv[0], args: $argv[1:], fileExtensions: $ext}
      '
    )"
    entries="$(jq -c --arg n "${name}" --argjson e "${entry}" '.[$n] = $e' <<< "${entries}")"
  done < <(jq -r 'keys[]' <<< "${ext_map}")

  local owned_names owned_before prune file applied_names
  owned_names="$(jq -c 'keys' <<< "${entries}")"
  owned_before="$(dyai_lsp::owned_get copilot)"
  prune="$(jq -c --argjson keep "${owned_names}" '(. // []) - $keep' <<< "${owned_before}")"
  # shellcheck disable=SC2312 # path_join only builds a path string, it cannot fail here
  file="$(dybatpho::path_join "${COPILOT_HOME:-$(dybatpho::path_join "${HOME}" ".copilot")}" "lsp-config.json")"
  applied_names="$(
    __dyai_lsp_write_json_block copilot "${file}" "lspServers" "${entries}" "${prune}" "${owned_before}"
  )"
  dyai_lsp::owned_set copilot "${applied_names}"
}

#######################################
# @description Write every Neovim language server into opencode's config,
#   launcher-wrapped, pruning servers dyai wrote before that are no longer in
#   the manifest. Runs only if `opencode` is on PATH; leaves the file
#   untouched (with a warning) when the manifest is missing or invalid.
# @noargs
# @env OPENCODE_CONFIG string [default: ~/.config/opencode/opencode.json]
# @env XDG_CACHE_HOME string Base of the manifest and owned-state files
#######################################
function dyai_lsp::setup_opencode {
  dybatpho::is command opencode || return 0
  local manifest
  # shellcheck disable=SC2312 # xdg_cache_dir only builds a path string, it cannot fail here
  manifest="$(dybatpho::path_join "$(dybatpho::xdg_cache_dir dyai)" "lsp.json")"
  if ! dybatpho::is file "${manifest}"; then
    dybatpho::warn "No dyai-lsp manifest at ${manifest}, skip opencode"
    return 1
  fi
  if ! jq -e . "${manifest}" &> /dev/null; then
    dybatpho::warn "Invalid dyai-lsp manifest ${manifest}, skip opencode"
    return 1
  fi
  local entries name server_json argv init_opts entry
  entries="{}"
  # shellcheck disable=SC2312 # a malformed manifest yields no names, a safe no-op loop
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    server_json="$(jq -c --arg n "${name}" '.servers[] | select(.name == $n)' "${manifest}")"
    argv="$(dyai_lsp::launch_argv "${server_json}")"
    # shellcheck disable=SC2312 # a bad server entry yields {}, a safe no-op default
    init_opts="$(jq -c '.init_options // {}' <<< "${server_json}")"
    entry="$(
      jq -n --argjson argv "${argv}" --argjson server "${server_json}" --argjson init "${init_opts}" '
        {command: $argv, extensions: (($server.extensions // {}) | keys_unsorted)}
        + (if ($init | length) > 0 then {initialization: $init} else {} end)
      '
    )"
    entries="$(jq -c --arg n "${name}" --argjson e "${entry}" '.[$n] = $e' <<< "${entries}")"
  done < <(jq -r '.servers[].name' "${manifest}")

  local owned_names owned_before prune file applied_names
  owned_names="$(jq -c 'keys' <<< "${entries}")"
  owned_before="$(dyai_lsp::owned_get opencode)"
  prune="$(jq -c --argjson keep "${owned_names}" '(. // []) - $keep' <<< "${owned_before}")"
  file="${OPENCODE_CONFIG:-$(dybatpho::path_join "${HOME}" ".config" "opencode" "opencode.json")}"
  applied_names="$(__dyai_lsp_write_json_block opencode "${file}" "lsp" "${entries}" "${prune}" "${owned_before}")"
  dyai_lsp::owned_set opencode "${applied_names}"
}

#######################################
# @description Write the Neovim language servers' primary extensions into
#   Hermes' `~/.hermes/config.yaml` (`.lsp.servers`), launcher-wrapped, keyed
#   by the Hermes built-in id when the server name maps to one, pruning
#   servers dyai wrote before that are no longer in the manifest. Runs only
#   if `hermes` is on PATH; leaves the file untouched (with a warning) when
#   the manifest is missing or invalid.
# @noargs
# @env XDG_CACHE_HOME string Base of the manifest and owned-state files
# @env HOME string Used to locate ~/.hermes/config.yaml
#######################################
function dyai_lsp::setup_hermes {
  dybatpho::is command hermes || return 0
  local manifest
  # shellcheck disable=SC2312 # xdg_cache_dir only builds a path string, it cannot fail here
  manifest="$(dybatpho::path_join "$(dybatpho::xdg_cache_dir dyai)" "lsp.json")"
  if ! dybatpho::is file "${manifest}"; then
    dybatpho::warn "No dyai-lsp manifest at ${manifest}, skip Hermes"
    return 1
  fi
  local ext_map
  # shellcheck disable=SC2312 # a malformed manifest yields no output, caught below
  ext_map="$(dyai_lsp::primary_extensions "${manifest}" 2> /dev/null)"
  if ! jq -e . <<< "${ext_map}" &> /dev/null; then
    dybatpho::warn "Invalid dyai-lsp manifest ${manifest}, skip Hermes"
    return 1
  fi
  local entries name server_json ext_json argv exts init_opts entry id
  entries="{}"
  # shellcheck disable=SC2312 # a malformed ext_map yields no keys, a safe no-op loop
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    server_json="$(jq -c --arg n "${name}" '.servers[] | select(.name == $n)' "${manifest}")"
    # shellcheck disable=SC2312 # a name read from ext_map's own keys always has an entry
    ext_json="$(jq -c --arg n "${name}" '.[$n]' <<< "${ext_map}")"
    argv="$(dyai_lsp::launch_argv "${server_json}")"
    exts="$(jq -c 'keys_unsorted' <<< "${ext_json}")"
    # shellcheck disable=SC2312 # a bad server entry yields {}, a safe no-op default
    init_opts="$(jq -c '.init_options // {}' <<< "${server_json}")"
    entry="$(
      jq -n --argjson argv "${argv}" --argjson exts "${exts}" --argjson init "${init_opts}" '
        {command: $argv, extensions: $exts}
        + (if ($init | length) > 0 then {initialization_options: $init} else {} end)
      '
    )"
    id="$(__dyai_lsp_hermes_id "${name}")"
    entries="$(jq -c --arg k "${id}" --argjson e "${entry}" '.[$k] = $e' <<< "${entries}")"
  done < <(jq -r 'keys[]' <<< "${ext_map}")

  local owned_names owned_before prune file applied_names
  owned_names="$(jq -c 'keys' <<< "${entries}")"
  owned_before="$(dyai_lsp::owned_get hermes)"
  prune="$(jq -c --argjson keep "${owned_names}" '(. // []) - $keep' <<< "${owned_before}")"
  file="$(dybatpho::path_join "${HOME}" ".hermes" "config.yaml")"
  applied_names="$(__dyai_lsp_write_yaml_block hermes "${file}" "${entries}" "${prune}" "${owned_before}")"
  dyai_lsp::owned_set hermes "${applied_names}"
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

#######################################
# @description Print the serena MCP server definition for one context
# @arg $1 string serena context (codex, ide, antigravity, ...)
# @env CONFIG_FILE string Read for global.lsp.serena.ref
# @stdout JSON `{command, args, env}`
#######################################
function dyai_lsp::serena_entry {
  local context ref
  dybatpho::expect_args context -- "$@"
  # shellcheck disable=SC2312 # a bad config read yields "", caught by the caller
  ref="$(dyai::config_json '.global.lsp.serena.ref // ""' | jq -r .)"
  jq -n --arg ref "${ref}" --arg context "${context}" '
    {
      command: "uvx",
      args: ["-p", "3.13", "--from", ("git+https://github.com/oraios/serena@" + $ref),
             "serena", "start-mcp-server", "--project-from-cwd",
             "--context", $context, "--open-web-dashboard", "false"],
      env: {SERENA_USAGE_REPORTING: "false"}
    }
  '
}

#######################################
# @description Build {basename, argv} for every PATH-only serena language
#   (gopls, lua_ls — Ruling 6) that is present in the manifest
# @noargs
# @env XDG_CACHE_HOME string Base of the manifest file
# @stdout JSON array of `{basename, argv}`
#######################################
function __dyai_lsp_serena_shim_targets {
  local manifest name server_json cmd base argv out
  # shellcheck disable=SC2312 # xdg_cache_dir only builds a path string, it cannot fail here
  manifest="$(dybatpho::path_join "$(dybatpho::xdg_cache_dir dyai)" "lsp.json")"
  out="[]"
  if dybatpho::is file "${manifest}"; then
    for name in gopls lua_ls; do
      # shellcheck disable=SC2312 # no match yields empty, the guard below skips it
      server_json="$(jq -c --arg n "${name}" '.servers[] | select(.name == $n)' "${manifest}" 2> /dev/null)"
      [[ -n "${server_json}" ]] || continue
      cmd="$(jq -r '.command' <<< "${server_json}")"
      base="${cmd##*/}"
      argv="$(dyai_lsp::launch_argv "${server_json}")"
      out="$(jq -c --arg b "${base}" --argjson a "${argv}" '. + [{basename: $b, argv: $a}]' <<< "${out}")"
    done
  fi
  printf '%s\n' "${out}"
}

#######################################
# @description Regenerate the serena PATH shims for gopls/lua_ls, removing any
#   shim no longer wanted (the shim dir is entirely dyai-owned)
# @arg $1 string Shim directory
# @stdout The number of shims now present (0, 1 or 2)
#######################################
function __dyai_lsp_write_serena_shims {
  local shim_dir targets wanted shim_file base n i quoted tmp dest
  dybatpho::expect_args shim_dir -- "$@"
  dybatpho::ensure_dir "${shim_dir}" > /dev/null
  targets="$(__dyai_lsp_serena_shim_targets)"
  wanted="$(jq -c '[.[].basename]' <<< "${targets}")"
  for shim_file in "${shim_dir}"/*; do
    [[ -e "${shim_file}" ]] || continue
    base="$(basename "${shim_file}")"
    # shellcheck disable=SC2312 # a bad wanted list yields false, which just removes the file
    if ! jq -e --arg b "${base}" 'index($b) != null' <<< "${wanted}" > /dev/null; then
      rm -f "${shim_file}"
    fi
  done
  n="$(jq 'length' <<< "${targets}")"
  for ((i = 0; i < n; i++)); do
    base="$(jq -r ".[${i}].basename" <<< "${targets}")"
    quoted="$(jq -r ".[${i}].argv | map(@sh) | join(\" \")" <<< "${targets}")"
    dybatpho::create_temp tmp "sh" "dyai-lsp-shim" "${shim_dir}"
    printf '#!/usr/bin/env bash\nexec %s "$@"\n' "${quoted}" > "${tmp}"
    chmod +x "${tmp}"
    dest="$(dybatpho::path_join "${shim_dir}" "${base}")"
    mv "${tmp}" "${dest}"
  done
  printf '%s\n' "${n}"
}

#######################################
# @description Print the path serena reads for ls_specific_settings/projects
# @noargs
# @stdout Path to ${SERENA_HOME:-~/.serena}/serena_config.yml
#######################################
function __dyai_lsp_serena_config_file {
  local serena_home
  # shellcheck disable=SC2312 # path_join only builds a path string, it cannot fail here
  serena_home="${SERENA_HOME:-$(dybatpho::path_join "${HOME}" ".serena")}"
  dybatpho::path_join "${serena_home}" "serena_config.yml"
}

#######################################
# @description Merge the manifest's `ls_base_cmd` overrides into
#   `${SERENA_HOME:-~/.serena}/serena_config.yml`'s `ls_specific_settings`,
#   pruning stale dyai-owned languages first, idempotently, and ensuring a
#   top-level `projects` key exists. A language that already exists there and
#   is not in the caller's owned-state list is left untouched (a user's own
#   hand-written entry), with one warning.
# @noargs
# @env XDG_CACHE_HOME string Base of the manifest and owned-state files
#######################################
function dyai_lsp::setup_serena_config {
  local manifest name server_json argv lang entries
  # shellcheck disable=SC2312 # xdg_cache_dir only builds a path string, it cannot fail here
  manifest="$(dybatpho::path_join "$(dybatpho::xdg_cache_dir dyai)" "lsp.json")"
  entries="{}"
  if dybatpho::is file "${manifest}"; then
    for name in "${!DYAI_LSP_SERENA_LANG[@]}"; do
      # shellcheck disable=SC2312 # no match yields empty, the guard below skips it
      server_json="$(jq -c --arg n "${name}" '.servers[] | select(.name == $n)' "${manifest}" 2> /dev/null)"
      [[ -n "${server_json}" ]] || continue
      argv="$(dyai_lsp::launch_argv "${server_json}")"
      lang="${DYAI_LSP_SERENA_LANG[${name}]}"
      entries="$(jq -c --arg l "${lang}" --argjson a "${argv}" '.[$l] = {ls_base_cmd: $a}' <<< "${entries}")"
    done
  fi

  local file dir
  file="$(__dyai_lsp_serena_config_file)"
  dir="$(dirname "${file}")"
  dybatpho::ensure_dir "${dir}" > /dev/null
  dybatpho::is file "${file}" || : > "${file}"

  local current_json cur_norm owned_before collided filtered_entries applied_names key
  # shellcheck disable=SC2312 # a malformed file falls back to {}, forcing a rewrite attempt
  current_json="$(yq -o=json '.ls_specific_settings // {}' "${file}" 2> /dev/null || printf '{}')"
  cur_norm="$(jq -cS . <<< "${current_json}" 2> /dev/null || printf '{}')"
  owned_before="$(dyai_lsp::owned_get serena)"
  collided="$(
    jq -cn --argjson entries "${entries}" --argjson owned "${owned_before}" --argjson cur "${current_json}" '
      [ ($entries | keys_unsorted[]) as $k
        | select(($cur | has($k)) and (($owned // []) | index($k) | not))
        | $k
      ]
    '
  )"
  # shellcheck disable=SC2312 # a malformed collided list yields no rows, a safe no-op loop
  while IFS= read -r key; do
    [[ -n "${key}" ]] || continue
    dybatpho::warn \
      "Leaving serena's hand-written ls_specific_settings.${key} untouched in ${file}: dyai does not own it"
  done < <(jq -r '.[]' <<< "${collided}")
  filtered_entries="$(
    jq -c --argjson collided "${collided}" 'with_entries(select(.key as $k | ($collided | index($k)) | not))' \
      <<< "${entries}"
  )"
  applied_names="$(jq -c 'keys' <<< "${filtered_entries}")"

  local prune new_block new_norm projects_present
  prune="$(jq -c --argjson keep "${applied_names}" '(. // []) - $keep' <<< "${owned_before}")"
  new_block="$(
    jq --argjson entries "${filtered_entries}" --argjson prune "${prune}" '
      reduce $prune[] as $k (.; del(.[$k]))
      | reduce ($entries | keys_unsorted[]) as $k (.; .[$k] = $entries[$k])
    ' <<< "${current_json}"
  )"
  new_norm="$(jq -cS . <<< "${new_block}")"
  # shellcheck disable=SC2312 # a malformed/empty file reads as absent, which forces the write below
  projects_present="$(yq -o=json '(.projects != null)' "${file}" 2> /dev/null || printf 'false')"
  if [[ "${cur_norm}" == "${new_norm}" && "${projects_present}" == "true" ]]; then
    dybatpho::debug "serena ls_specific_settings already up to date in ${file}"
    dyai_lsp::owned_set serena "${applied_names}"
    return 0
  fi
  local yq_expr
  yq_expr='.ls_specific_settings = (strenv(E) | fromjson) | .projects = (.projects // [])'
  if E="${new_block}" yq -i "${yq_expr}" "${file}"; then
    dybatpho::info "Updated serena ls_specific_settings in ${file}"
  else
    dybatpho::warn "Could not update serena ls_specific_settings in ${file}"
  fi
  dyai_lsp::owned_set serena "${applied_names}"
}

#######################################
# @description Bridge Neovim's language servers to Codex, Gemini and agy
#   through serena: registers the serena MCP server (Codex gets an extra
#   startup_timeout_sec, the first `uvx` fetch is slow), writes PATH shims for
#   gopls/lua_ls, and merges the launcher-wrapped `ls_base_cmd` overrides into
#   serena_config.yml. Skips with a warning when `uvx` is missing.
# @noargs
# @env CONFIG_FILE string Read for global.lsp.serena.{ref,contexts}
# @env XDG_CACHE_HOME string Base of the manifest and owned-state files
# @env XDG_DATA_HOME string Base of the serena-shims directory
# @exitcode 1 uvx is missing, or global.lsp.serena.ref is unset
#######################################
function dyai_lsp::setup_serena {
  if ! dybatpho::is command uvx; then
    dybatpho::warn "uvx is not installed, skip serena"
    return 1
  fi
  local ref
  # shellcheck disable=SC2312 # a bad config read yields "", caught below
  ref="$(dyai::config_json '.global.lsp.serena.ref // ""' | jq -r .)"
  if [[ -z "${ref}" || "${ref}" == "null" ]]; then
    dybatpho::warn "global.lsp.serena.ref is not set in the dyai config, skip serena"
    return 1
  fi

  local shim_dir shim_count
  # shellcheck disable=SC2312 # xdg_data_dir only builds a path string, it cannot fail here
  shim_dir="$(dybatpho::path_join "$(dybatpho::xdg_data_dir dyai)" "serena-shims")"
  shim_count="$(__dyai_lsp_write_serena_shims "${shim_dir}")"

  local contexts_json agent context base
  contexts_json="$(dyai::config_json '.global.lsp.serena.contexts // {}')"
  for agent in gemini agy codex; do
    context="$(jq -r --arg a "${agent}" '.[$a] // ""' <<< "${contexts_json}")"
    [[ -n "${context}" ]] || continue
    dybatpho::is command "${agent}" || continue
    base="$(dyai_lsp::serena_entry "${context}")"
    if [[ "${shim_count}" -gt 0 ]]; then
      base="$(jq --arg p "${shim_dir}:${PATH}" '.env.PATH = $p' <<< "${base}")"
    fi
    local file
    case "${agent}" in
      gemini)
        file="$(dybatpho::path_join "${HOME}" ".gemini" "settings.json")"
        dyai::mcp_merge_json "${file}" mcpServers serena "${base}"
        ;;
      agy)
        file="$(dybatpho::path_join "${HOME}" ".gemini" "config" "mcp_config.json")"
        dyai::mcp_merge_json "${file}" mcpServers serena "${base}"
        ;;
      codex)
        local centry chome
        centry="$(jq '. + {startup_timeout_sec: 60}' <<< "${base}")"
        chome="${CODEX_HOME:-$(dybatpho::path_join "${HOME}" ".codex")}"
        file="$(dybatpho::path_join "${chome}" "config.toml")"
        dyai::mcp_merge_yq "${file}" toml serena "${centry}"
        ;;
      *) ;;
    esac
  done

  dyai_lsp::setup_serena_config
}
