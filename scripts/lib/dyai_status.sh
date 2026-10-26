# @file dyai_status.sh
# @brief Report drift between the dyai config and what each agent actually has
# @description `dyai status` compares what `~/.config/dyai/config.yaml`
# declares with what is installed for every agent present on this machine:
# skills, Claude plugins, subagents, MCP servers, notify hooks and the
# translated permission policy. It prints one line per drift and stays silent
# on a fully armed machine, so it can run at every session start (the Intent
# Loop's "armed vs declared" check). It reads files only: no network and no
# agent CLI is called. Subagents are checked through the hashes dyai recorded
# when it installed them; the declared list itself lives in a pinned repo that
# would need a download. Sourced by dyai.sh (not executed).
# shellcheck shell=bash

#######################################
# @description Print one drift line and count it
# @arg $1 string Agent name
# @arg $2 string Kind of item (skill, plugin, subagent, mcp, hook, policy)
# @arg $3 string Name of the item
# @arg $4 string What is wrong
#######################################
function dyai_status::drift {
  local agent kind name problem
  dybatpho::expect_args agent kind name problem -- "$@"
  printf '%s %s %s: %s\n' "${agent}" "${kind}" "${name}" "${problem}"
  DYAI_STATUS_DRIFT=$((DYAI_STATUS_DRIFT + 1))
}

#######################################
# @description Check the shared skills: present, and unchanged since dyai installed them
# @noargs
#######################################
function dyai_status::skills {
  local skill name target
  # shellcheck disable=SC2312 # a bad config read yields no rows, which is a safe no-op
  while IFS= read -r skill; do
    [[ -n "${skill}" ]] || continue
    name="${skill##*@}"
    target="$(dybatpho::path_join "${SKILLS_DIR:?}" "${name}")"
    if ! dybatpho::is dir "${target}"; then
      dyai_status::drift all skill "${name}" missing
      continue
    fi
    # shellcheck disable=SC2310 # a plain yes/no; no hash recorded reads as no
    if dyai::locally_edited skills "${name}" "${target}"; then
      dyai_status::drift all skill "${name}" "LOCAL EDITS"
    fi
  done < <(dyai::config_json '.global.skills // []' | jq -r '.[]')
}

#######################################
# @description Check Claude plugins and the subagents dyai recorded
# @noargs
#######################################
function dyai_status::claude {
  dybatpho::is command claude || return 0
  local installed plugin hash_dir file leaf dest
  installed="$(dybatpho::path_join "${PLUGINS_DIR:?}" "installed_plugins.json")"
  # shellcheck disable=SC2312 # a bad config read yields no rows, which is a safe no-op
  while IFS= read -r plugin; do
    [[ -n "${plugin}" ]] || continue
    # shellcheck disable=SC2310 # a missing or non-matching file is a plain no
    dyai::in_json_file "${installed}" ".plugins | has(\"${plugin}\")" \
      || dyai_status::drift claude plugin "${plugin}" missing
  done < <(dyai::config_json '(.agents.claude.plugins // []) + (.agents.claude.optional_plugins // [])' \
    | jq -r '.[]')
  hash_dir="$(dybatpho::path_join "${HOME}" ".cache" "dyai" "installed" "subagents")"
  dybatpho::is dir "${hash_dir}" || return 0
  for file in "${hash_dir}"/*.sha256; do
    dybatpho::is file "${file}" || continue
    leaf="$(basename "${file}" .sha256)"
    dest="$(dybatpho::path_join "${HOME}" ".claude" "agents" "${leaf}.md")"
    if ! dybatpho::is file "${dest}"; then
      dyai_status::drift claude subagent "${leaf}" missing
      continue
    fi
    # shellcheck disable=SC2310 # a plain yes/no
    if dyai::locally_edited subagents "${leaf}" "${dest}"; then
      dyai_status::drift claude subagent "${leaf}" "LOCAL EDITS"
    fi
  done
}

#######################################
# @description Tell whether a config file holds a key, false when the file is missing
# @arg $1 string Path of the file
# @arg $2 string yq format of the file: json, toml or yaml
# @arg $3 string yq path expression that must not be null
# @exitcode 0 The file exists and the expression is set
#######################################
function dyai_status::has_key {
  local file format expr
  dybatpho::expect_args file format expr -- "$@"
  dybatpho::is file "${file}" || return 1
  local value
  value="$(yq -p="${format}" -o=json -I=0 "${expr}" "${file}" 2> /dev/null)" || return 1
  [[ -n "${value}" && "${value}" != "null" ]]
}

#######################################
# @description Check that every shared MCP server is registered in each installed agent
# @noargs
#######################################
function dyai_status::mcp {
  local servers name command dir chome
  servers="$(dyai::config_json '.global.mcp // {}')"
  # shellcheck disable=SC2312 # a bad config read yields no rows, which is a safe no-op
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    command="$(jq -r --arg n "${name}" '.[$n].command // ""' <<< "${servers}")"
    # dyai install skips a server whose command is missing, and says so then.
    if [[ -n "${command}" ]] && ! dybatpho::is command "${command}"; then
      continue
    fi
    # shellcheck disable=SC2310 # a plain yes/no
    if dybatpho::is command claude && ! dyai::claude_plugin_bundles "${name}"; then
      # shellcheck disable=SC2312 # the dir list is local and never fails
      while IFS= read -r dir; do
        [[ -n "$(dyai::claude_mcp_current "${dir}" "${name}")" ]] \
          || dyai_status::drift claude mcp "${name}" "not registered in ${dir}"
      done < <(dyai::claude_config_dirs)
    fi
    dyai_status::mcp_file gemini "${HOME}/.gemini/settings.json" json ".mcpServers[\"${name}\"]" "${name}"
    dyai_status::mcp_file agy "${HOME}/.gemini/config/mcp_config.json" json ".mcpServers[\"${name}\"]" "${name}"
    chome="${COPILOT_HOME:-${HOME}/.copilot}"
    dyai_status::mcp_file copilot "${chome}/mcp-config.json" json ".mcpServers[\"${name}\"]" "${name}"
    dyai_status::mcp_file opencode "${OPENCODE_CONFIG:-${HOME}/.config/opencode/opencode.json}" json \
      ".mcp[\"${name}\"]" "${name}"
    chome="${CODEX_HOME:-${HOME}/.codex}"
    dyai_status::mcp_file codex "${chome}/config.toml" toml ".mcp_servers[\"${name}\"]" "${name}"
    dyai_status::mcp_file hermes "${HOME}/.hermes/config.yaml" yaml ".mcp_servers[\"${name}\"]" "${name}"
  done < <(jq -r 'keys[]?' <<< "${servers}")
}

#######################################
# @description Report an MCP server missing from one installed agent's config file
# @arg $1 string Agent command name
# @arg $2 string Config file path
# @arg $3 string yq format of the file
# @arg $4 string yq path of the server entry
# @arg $5 string Server name
#######################################
function dyai_status::mcp_file {
  local agent file format expr name
  dybatpho::expect_args agent file format expr name -- "$@"
  dybatpho::is command "${agent}" || return 0
  # shellcheck disable=SC2310 # a plain yes/no
  dyai_status::has_key "${file}" "${format}" "${expr}" \
    || dyai_status::drift "${agent}" mcp "${name}" "not in ${file}"
}

#######################################
# @description Check the notify hooks and the permission policy files dyai writes
# @noargs
#######################################
function dyai_status::hooks_and_policy {
  local hooks perms chome
  # shellcheck disable=SC2312 # a bad config read yields an empty string, a safe no-op
  hooks="$(dyai::config_json '(.global.hooks.stop.run // "") + (.global.hooks.input.run // "")' | jq -r .)"
  if [[ -n "${hooks}" ]]; then
    # shellcheck disable=SC2310 # a plain yes/no
    if dybatpho::is command gemini \
      && ! dyai_status::has_key "${HOME}/.gemini/settings.json" json \
        '.hooks.AfterAgent[] | select(.hooks[0].name == "dyai-notify")'; then
      dyai_status::drift gemini hook dyai-notify "not in ~/.gemini/settings.json"
    fi
    chome="${COPILOT_HOME:-${HOME}/.copilot}"
    if dybatpho::is command copilot && ! dybatpho::is file "${chome}/hooks/dyai.json"; then
      dyai_status::drift copilot hook dyai-notify "missing ${chome}/hooks/dyai.json"
    fi
    chome="${CODEX_HOME:-${HOME}/.codex}"
    # shellcheck disable=SC2310 # a plain yes/no
    if dybatpho::is command codex && ! dyai_status::has_key "${chome}/config.toml" toml '.hooks.Stop'; then
      dyai_status::drift codex hook stop "not in ${chome}/config.toml"
    fi
  fi
  perms="$(dyai::config_json '.global.policy.permissions // {}')"
  # shellcheck disable=SC2312 # a bad config read is treated as no rule at all
  jq -e '((.ask // []) + (.deny // []) | length) > 0' <<< "${perms}" > /dev/null || return 0
  if dybatpho::is command gemini && ! dybatpho::is file "${HOME}/.gemini/policies/dyai.toml"; then
    dyai_status::drift gemini policy permissions "missing ~/.gemini/policies/dyai.toml"
  fi
  chome="${CODEX_HOME:-${HOME}/.codex}"
  if dybatpho::is command codex && ! dybatpho::is file "${chome}/rules/dyai.rules"; then
    dyai_status::drift codex policy permissions "missing ${chome}/rules/dyai.rules"
  fi
  # shellcheck disable=SC2310 # a plain yes/no
  if dybatpho::is command opencode \
    && ! dyai_status::has_key "${OPENCODE_CONFIG:-${HOME}/.config/opencode/opencode.json}" json '.permission'; then
    dyai_status::drift opencode policy permissions "no permission block"
  fi
}

#######################################
# @description Report every drift between the dyai config and the installed agents
# @arg $1 bool true to print nothing at all on a clean machine
# @stdout One line per drift, then a summary unless quiet
# @exitcode 0 Nothing drifted
# @exitcode 1 At least one drift
#######################################
function dyai_status::main {
  local quiet
  dybatpho::expect_args quiet -- "$@"
  dyai::paths
  if ! dybatpho::is file "${CONFIG_FILE:?}" || ! dybatpho::is command jq || ! dybatpho::is command yq; then
    [[ "${quiet}" == "true" ]] || printf '%s\n' "dyai: no config or no jq/yq; nothing to compare"
    return 0
  fi
  DYAI_STATUS_DRIFT=0
  dyai_status::skills
  dyai_status::claude
  dyai_status::mcp
  dyai_status::hooks_and_policy
  if ((DYAI_STATUS_DRIFT > 0)); then
    [[ "${quiet}" == "true" ]] \
      || printf '%s\n' "${DYAI_STATUS_DRIFT} drift(s); run dyai install, or keep the LOCAL EDITS on purpose"
    return 1
  fi
  [[ "${quiet}" == "true" ]] || printf '%s\n' "dyai: every agent matches the config"
  return 0
}
