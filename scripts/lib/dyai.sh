# @file dyai.sh
# @brief Install AI-agent marketplaces, plugins, skills, MCP servers, policy and hooks
# @description The global install logic behind `dyai install` and the setup hook.
# Reads the single declarative source `~/.config/dyai/config.yaml` and brings
# every supported agent's extensions in line with it. Sourced (not executed);
# the caller sources dybatpho first and owns strict mode.
# shellcheck shell=bash

# The skills CLI is pinned, so an apply never runs a release nobody looked at.
SKILLS_CLI="skills@1.7.2"

# jq definitions shared by the permission translators. The input is
# global.policy.permissions, in Claude's syntax: `Bash(<command pattern>)`,
# `Read(<glob>)`, `Edit(<glob>)`.
# - cmds($kind): the Bash rules of ask or deny as {p, glued}, where p is the
#   command prefix and glued is true for `p*` (no word boundary, as in
#   `chezmoi-dycrypt*`). The rtk spellings exist only for Claude's rtk hook and
#   are dropped. An ask prefix that deny also lists is dropped: deny wins.
# - literal: true for a rule with no `*` left inside its prefix (`git * main`
#   has one); only a glob-matching agent can express the others.
# - paths($kind; $tool): the globs of the Read or Edit rules of ask or deny.
# dyshellint disable=SC2016 a jq program; its $names are jq variables, not shell ones
DYAI_PERM_JQ='
def bash_rules($kind): (.[$kind] // [])
  | map(select(type == "string" and startswith("Bash(") and endswith(")")) | .[5:-1]
    | select(startswith("rtk ") | not)
    | if endswith(":*") or endswith(" *") then {p: .[:-2], glued: false}
      elif endswith("*") then {p: .[:-1], glued: true}
      else {p: ., glued: false} end)
  | unique_by(.p);
def cmds($kind):
  if $kind == "ask" then
    (bash_rules("deny") | map(.p)) as $deny
    | bash_rules("ask") | map(select(.p as $p | $deny | index($p) | not))
  else bash_rules("deny") end;
def literal: .p | contains("*") | not;
def paths($kind; $tool): (.[$kind] // [])
  | map(select(type == "string" and startswith($tool + "(") and endswith(")"))
    | .[($tool | length) + 1:-1]);
'

#######################################
# @description True when this machine has an AMD GPU (ROCm) for laya's torch build
# @noargs
# @exitcode 0 An AMD GPU / ROCm is present
#######################################
function dyai::has_amd_gpu {
  [[ -d /opt/rocm ]] || dybatpho::is command rocminfo
}

#######################################
# @description Check a filter against a JSON file, false when the file is missing
# @arg $1 string Path of the JSON file
# @arg $2 string jq filter that yields true or false
# @exitcode 0 The file exists and the filter yields true
#######################################
function dyai::in_json_file {
  local file filter
  dybatpho::expect_args file filter -- "$@"
  dybatpho::is file "${file}" || return 1
  jq -e "${filter}" "${file}" > /dev/null
}

#######################################
# @description Read a section of the dyai config as compact JSON
# @arg $1 string yq path expression, e.g. '.global.mcp // {}'
# @stdout The section as JSON, or the empty object/array the expression defaults to
#######################################
function dyai::config_json {
  local expr
  dybatpho::expect_args expr -- "$@"
  yq -o=json -I=0 "${expr}" "${CONFIG_FILE}"
}

#######################################
# @description Register every Claude marketplace the config names that Claude does not know yet
# @noargs
#######################################
function dyai::setup_marketplaces {
  local known_file marketplaces name source
  known_file="$(dybatpho::path_join "${PLUGINS_DIR}" "known_marketplaces.json")"
  marketplaces="$(dyai::config_json '.agents.claude.marketplaces // {}')"
  # One field per source: a tab is IFS whitespace, so `read` would collapse an
  # empty repo or url field and shift the ones after it.
  # shellcheck disable=SC2312 # a bad config read yields no rows, which is a safe no-op
  while IFS=$'\t' read -r name source; do
    [[ -n "${name}" ]] || continue
    # shellcheck disable=SC2310 # a missing or non-matching file is a plain no
    if dyai::in_json_file "${known_file}" "has(\"${name}\")"; then
      dybatpho::debug "Marketplace ${name} already known"
      continue
    fi
    dybatpho::info "Add marketplace ${name}"
    # stdin is the loop's list; a command that reads it would swallow the rest.
    claude plugin marketplace add "${source}" < /dev/null || dybatpho::warn "Could not add marketplace ${name}"
  done < <(jq -r 'to_entries[] | [.key, (.value.source.repo // .value.source.url // "")] | @tsv' <<< "${marketplaces}")
}

#######################################
# @description Install every Claude plugin the config names that is not installed yet
# @noargs
#######################################
function dyai::setup_plugins {
  local installed_file plugin
  installed_file="$(dybatpho::path_join "${PLUGINS_DIR}" "installed_plugins.json")"
  # shellcheck disable=SC2312 # a bad config read yields no rows, which is a safe no-op
  while IFS= read -r plugin; do
    [[ -n "${plugin}" ]] || continue
    # shellcheck disable=SC2310 # a missing or non-matching file is a plain no
    if dyai::in_json_file "${installed_file}" ".plugins | has(\"${plugin}\")"; then
      dybatpho::debug "Plugin ${plugin} already installed"
      continue
    fi
    dybatpho::info "Install plugin ${plugin}"
    claude plugin install "${plugin}" < /dev/null || dybatpho::warn "Could not install plugin ${plugin}"
  done < <(dyai::config_json '.agents.claude.plugins // []' | jq -r '.[]')
}

#######################################
# @description Install every skill in global.skills missing from the global skills directory
# @noargs
#######################################
function dyai::setup_skills {
  local skill name target
  # shellcheck disable=SC2312 # a bad config read yields no rows, which is a safe no-op
  while IFS= read -r skill; do
    [[ -n "${skill}" ]] || continue
    name="${skill##*@}"
    target="$(dybatpho::path_join "${SKILLS_DIR}" "${name}")"
    if dybatpho::is dir "${target}"; then
      dybatpho::debug "Skill ${name} already installed"
      continue
    fi
    dybatpho::info "Install skill ${skill}"
    bunx "${SKILLS_CLI}" add "${skill}" -g -y < /dev/null || dybatpho::warn "Could not install skill ${skill}"
  done < <(dyai::config_json '.global.skills // []' | jq -r '.[]')
}

#######################################
# @description Print every Claude configuration directory of this machine
# @noargs
# @stdout One directory per line, the default one first
#######################################
function dyai::claude_config_dirs {
  local dir
  printf '%s\n' "${DEFAULT_CONFIG_DIR}"
  for dir in "${ENTERPRISE_DIR}"/*/.claude "${ENTERPRISE_DIR}"/*/*/.claude; do
    if dybatpho::is dir "${dir}"; then
      printf '%s\n' "${dir}"
    fi
  done
}

#######################################
# @description Run claude against one configuration directory
# @arg $1 string Configuration directory
# @arg $@ string Arguments of claude, after the directory
#######################################
function dyai::claude_in {
  local dir
  dybatpho::expect_args dir -- "$@"
  shift
  # The default configuration is the one claude reads when CLAUDE_CONFIG_DIR is unset.
  if [[ "${dir}" == "${DEFAULT_CONFIG_DIR}" ]]; then
    env -u CLAUDE_CONFIG_DIR claude "$@"
  else
    CLAUDE_CONFIG_DIR="${dir}" claude "$@"
  fi
}

#######################################
# @description Print the MCP server definition one Claude configuration should hold
# @arg $1 string Configuration directory
# @arg $2 string Name of the server
# @arg $3 string Server definition as JSON
# @stdout The definition, scoped to that configuration
#######################################
function dyai::claude_mcp_definition {
  local dir name definition
  dybatpho::expect_args dir name definition -- "$@"
  # filesystem is scoped to the enterprise tree in an enterprise config dir,
  # so an enterprise-context agent never sees personal or community files.
  if [[ "${name}" == "filesystem" && "${dir}" == "${ENTERPRISE_DIR}"/* ]]; then
    jq -c --arg d "${ENTERPRISE_DIR}" '.args = [.args[0], $d]' <<< "${definition}"
  else
    printf '%s\n' "${definition}"
  fi
}

#######################################
# @description Print the user-scope registration of an MCP server in one Claude configuration
# @arg $1 string Configuration directory
# @arg $2 string Name of the server
# @stdout The registered definition as sorted compact JSON, or nothing when absent
#######################################
function dyai::claude_mcp_current {
  local dir name
  dybatpho::expect_args dir name -- "$@"
  local state_file
  # The default configuration keeps its state next to the directory, not in it.
  if [[ "${dir}" == "${DEFAULT_CONFIG_DIR}" ]]; then
    state_file="$(dybatpho::path_join "${HOME}" ".claude.json")"
  else
    state_file="$(dybatpho::path_join "${dir}" ".claude.json")"
  fi
  dybatpho::is file "${state_file}" || return 0
  # A corrupt state file reads as absent, not an abort.
  jq -cS --arg name "${name}" '.mcpServers[$name] // empty' "${state_file}" 2> /dev/null || true
}

#######################################
# @description Tell whether an enabled Claude plugin of the same name already bundles an MCP server
# @arg $1 string Name of the server
# @exitcode 0 A `<name>@<marketplace>` entry is in agents.claude.plugins
# @exitcode 1 No such plugin
#######################################
function dyai::claude_plugin_bundles {
  local name
  dybatpho::expect_args name -- "$@"
  # shellcheck disable=SC2312 # a bad config read lists no plugin, so the server is registered
  dyai::config_json '.agents.claude.plugins // []' \
    | jq -e --arg n "${name}" 'map(split("@")[0]) | index($n) != null' > /dev/null
}

#######################################
# @description Remove an MCP server from every Claude configuration where dyai registered it
# @arg $1 string Name of the server
# @arg $2 string The definition dyai would register, as JSON
#######################################
function dyai::drop_mcp_server {
  local name definition
  dybatpho::expect_args name definition -- "$@"
  local dir current wanted
  # shellcheck disable=SC2312 # the directories are globbed, the loop cannot fail on them
  while IFS= read -r dir; do
    # Only a registration that is exactly dyai's own is removed; a server the
    # user registered or customized under that name is theirs to keep.
    wanted="$(dyai::claude_mcp_definition "${dir}" "${name}" "${definition}" | jq -cS .)"
    current="$(dyai::claude_mcp_current "${dir}" "${name}")"
    [[ -n "${current}" && "${current}" == "${wanted}" ]] || continue
    dybatpho::info "Remove MCP server ${name} from ${dir}, its Claude plugin provides it"
    # dyshellint disable=SC2310 a failure only warns, the other configurations still run
    dyai::claude_in "${dir}" mcp remove --scope user "${name}" > /dev/null \
      || dybatpho::warn "Could not remove the duplicate MCP server ${name} from ${dir}"
  done < <(dyai::claude_config_dirs)
}

#######################################
# @description Register an MCP server in every Claude configuration where it is missing or differs
# @arg $1 string Name of the server
# @arg $2 string Server definition as JSON, as `claude mcp add-json` takes it
#######################################
function dyai::setup_mcp_server {
  local name definition
  dybatpho::expect_args name definition -- "$@"
  local dir current wanted def_dir
  # shellcheck disable=SC2312 # the directories are globbed, the loop cannot fail on them
  while IFS= read -r dir; do
    def_dir="$(dyai::claude_mcp_definition "${dir}" "${name}" "${definition}")"
    wanted="$(jq -cS . <<< "${def_dir}")"
    current="$(dyai::claude_mcp_current "${dir}" "${name}")"
    if [[ "${current}" == "${wanted}" ]]; then
      dybatpho::debug "MCP server ${name} already registered in ${dir}"
      continue
    fi
    dybatpho::info "Register MCP server ${name} in ${dir}"
    if [[ -n "${current}" ]]; then
      # dyshellint disable=SC2310 a failure only warns, the other configurations still run
      dyai::claude_in "${dir}" mcp remove --scope user "${name}" > /dev/null \
        || dybatpho::warn "Could not remove the outdated MCP server ${name} from ${dir}"
    fi
    # dyshellint disable=SC2310 a failure only warns, the other configurations still run
    dyai::claude_in "${dir}" mcp add-json --scope user "${name}" "${def_dir}" > /dev/null \
      || dybatpho::warn "Could not register MCP server ${name} in ${dir}"
  done < <(dyai::claude_config_dirs)
}

#######################################
# @description Merge one MCP server entry into a JSON config under a block key, idempotently
# @arg $1 string Path of the JSON config file (created as {} when missing)
# @arg $2 string Block key that holds the servers (mcpServers or mcp)
# @arg $3 string Server name
# @arg $4 string Entry as JSON, in that agent's own shape
#######################################
function dyai::mcp_merge_json {
  local file block name entry
  dybatpho::expect_args file block name entry -- "$@"
  local dir current want tmp
  dir="$(dirname "${file}")"
  dybatpho::is dir "${dir}" || mkdir -p "${dir}"
  dybatpho::is file "${file}" || printf '{}\n' > "${file}"
  # shellcheck disable=SC2312 # a malformed file falls back to {}, forcing a rewrite attempt rather than aborting
  current="$(jq -cS --arg b "${block}" --arg n "${name}" '.[$b][$n] // empty' "${file}" 2> /dev/null || printf '{}')"
  want="$(jq -cS . <<< "${entry}")"
  if [[ "${current}" == "${want}" ]]; then
    dybatpho::debug "MCP ${name} already registered in ${file}"
    return 0
  fi
  dybatpho::create_temp tmp "json" "dyai" "${dir}"
  if jq --arg b "${block}" --arg n "${name}" --argjson e "${entry}" \
    '.[$b] = (.[$b] // {}) | .[$b][$n] = $e' "${file}" > "${tmp}" && mv "${tmp}" "${file}"; then
    dybatpho::info "Registered MCP ${name} in ${file}"
  else
    dybatpho::warn "Could not register MCP ${name} in ${file}"
  fi
}

#######################################
# @description Merge one MCP server into a TOML or YAML config under `mcp_servers`, idempotently
# @arg $1 string Path of the config file (created empty when missing)
# @arg $2 string yq format: toml or yaml
# @arg $3 string Server name
# @arg $4 string Entry as JSON (yq converts it to the file's format)
#######################################
function dyai::mcp_merge_yq {
  local file fmt name entry
  dybatpho::expect_args file fmt name entry -- "$@"
  local dir current want
  dir="$(dirname "${file}")"
  dybatpho::is dir "${dir}" || mkdir -p "${dir}"
  dybatpho::is file "${file}" || : > "${file}"
  # shellcheck disable=SC2312 # a read error on a malformed file just forces a rewrite
  current="$(N="${name}" \
    yq -p="${fmt}" -o=json -I=0 '.mcp_servers[strenv(N)] // {}' "${file}" 2> /dev/null || echo '{}')"
  # yq drops an empty `args`/`env` when it re-emits section-style TOML, so the
  # read-back would never equal a `want` that still carries them. Normalise both
  # by dropping empty args/env before comparing, or the file churns every run.
  local norm
  norm='if ((.args? // []) | length) == 0 then del(.args) else . end'
  norm+=' | if ((.env? // {}) | length) == 0 then del(.env) else . end'
  want="$(jq -cS "${norm}" <<< "${entry}")"
  # shellcheck disable=SC2312 # normalizing the current entry; a read error forces a rewrite
  if [[ "$(jq -cS "${norm}" <<< "${current}")" == "${want}" ]]; then
    dybatpho::debug "MCP ${name} already registered in ${file}"
    return 0
  fi
  if E="${entry}" N="${name}" \
    yq -p="${fmt}" -o="${fmt}" -i '.mcp_servers[strenv(N)] = (strenv(E) | fromjson)' "${file}"; then
    dybatpho::info "Registered MCP ${name} in ${file}"
  else
    dybatpho::warn "Could not register MCP ${name} in ${file}"
  fi
}

#######################################
# @description Register an MCP server into every non-Claude agent that is installed
# @arg $1 string Server name
# @arg $2 string Base definition as JSON: {command, args, env}
#######################################
function dyai::setup_mcp_agents {
  local name base
  dybatpho::expect_args name base -- "$@"
  # Each writer ends in an if/else that warns, so it returns 0 even on failure
  # and a bad write for one agent never aborts the others.
  local file centry chome oentry
  if dybatpho::is command gemini; then
    file="$(dybatpho::path_join "${HOME}" ".gemini" "settings.json")"
    dyai::mcp_merge_json "${file}" mcpServers "${name}" "${base}"
  fi
  if dybatpho::is command agy; then
    file="$(dybatpho::path_join "${HOME}" ".gemini" "config" "mcp_config.json")"
    dyai::mcp_merge_json "${file}" mcpServers "${name}" "${base}"
  fi
  if dybatpho::is command copilot; then
    centry="$(jq -c '. + {type: "local", tools: ["*"]}' <<< "${base}")"
    chome="${COPILOT_HOME:-$(dybatpho::path_join "${HOME}" ".copilot")}"
    file="$(dybatpho::path_join "${chome}" "mcp-config.json")"
    dyai::mcp_merge_json "${file}" mcpServers "${name}" "${centry}"
  fi
  if dybatpho::is command opencode; then
    oentry="$(jq -c \
      '{type: "local", command: ([.command] + (.args // [])), environment: (.env // {}), enabled: true}' \
      <<< "${base}")"
    file="${OPENCODE_CONFIG:-$(dybatpho::path_join "${HOME}" ".config" "opencode" "opencode.json")}"
    dyai::mcp_merge_json "${file}" mcp "${name}" "${oentry}"
  fi
  if dybatpho::is command codex; then
    chome="${CODEX_HOME:-$(dybatpho::path_join "${HOME}" ".codex")}"
    file="$(dybatpho::path_join "${chome}" "config.toml")"
    dyai::mcp_merge_yq "${file}" toml "${name}" "${base}"
  fi
  if dybatpho::is command hermes; then
    file="$(dybatpho::path_join "${HOME}" ".hermes" "config.yaml")"
    dyai::mcp_merge_yq "${file}" yaml "${name}" "${base}"
  fi
}

#######################################
# @description Register every server in global.mcp into every installed MCP-capable agent
# @noargs
#######################################
function dyai::setup_mcp {
  local servers name command base
  servers="$(dyai::config_json '.global.mcp // {}')"
  # A scalar or otherwise malformed section yields no keys and is skipped.
  # shellcheck disable=SC2312 # a bad config read yields no rows, which is a safe no-op
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    command="$(jq -r --arg n "${name}" '.[$n].command // ""' <<< "${servers}")"
    if [[ -n "${command}" ]] && ! dybatpho::is command "${command}"; then
      dybatpho::warn "MCP server ${name} command not found (${command}), skip"
      continue
    fi
    base="$(jq -c --arg n "${name}" \
      '.[$n] | {command: .command, args: (.args // []), env: (.env // {})}' <<< "${servers}")"
    # The ROCm build of torch ships no kernels for the RDNA2 chips other than
    # gfx1030 (Radeon 680M, RX 6600, ...); they run the gfx1030 ones instead.
    if [[ "${name}" == "laya" ]] && dyai::has_amd_gpu; then
      local agents
      agents="$(PATH="${PATH}:/opt/rocm/bin" rocminfo 2> /dev/null || true)"
      if [[ "${agents}" =~ gfx103[1-6] ]]; then
        base="$(jq -c '.env += {HSA_OVERRIDE_GFX_VERSION: "10.3.0"}' <<< "${base}")"
      fi
    fi
    if dybatpho::is command claude; then
      local definition
      definition="$(jq -c '{type: "stdio"} + .' <<< "${base}")"
      # A Claude plugin of the same name already bundles this server; a
      # second registration would load every tool definition twice.
      if dyai::claude_plugin_bundles "${name}"; then
        dybatpho::debug "MCP server ${name} comes with its Claude plugin, skip for Claude"
        dyai::drop_mcp_server "${name}" "${definition}"
      else
        # shellcheck disable=SC2310 # a failure only warns, the other agents still run
        dyai::setup_mcp_server "${name}" "${definition}"
      fi
    fi
    dyai::setup_mcp_agents "${name}" "${base}"
  done < <(jq -r 'if type == "object" then keys[] else empty end' <<< "${servers}")
}

#######################################
# @description Apply a jq expression to a JSON config file, idempotently and merge-safe
# @arg $1 string Path of the JSON file (created as {} when missing)
# @arg $2 string jq expression that sets the wanted keys, leaving the rest intact
#######################################
function dyai::json_set {
  local file expr
  dybatpho::expect_args file expr -- "$@"
  shift 2
  local dir before after tmp
  dir="$(dirname "${file}")"
  dybatpho::is dir "${dir}" || mkdir -p "${dir}"
  dybatpho::is file "${file}" || printf '{}\n' > "${file}"
  # shellcheck disable=SC2312 # a malformed file falls back to {}, forcing a rewrite attempt rather than aborting
  before="$(jq -cS . "${file}" 2> /dev/null || printf '{}')"
  after="$(jq -cS "$@" "${expr}" <<< "${before}")"
  [[ "${before}" == "${after}" ]] && return 0
  dybatpho::create_temp tmp "json" "dyai" "${dir}"
  if jq "$@" "${expr}" "${file}" > "${tmp}" && mv "${tmp}" "${file}"; then
    dybatpho::info "Updated ${file}"
  else
    dybatpho::warn "Could not update ${file}"
  fi
}

#######################################
# @description Set Gemini CLI's baseline settings: schema, shared AGENTS.md, checkpoints, privacy
# @noargs
#######################################
function dyai::setup_gemini {
  dybatpho::is command gemini || return 0
  local file expr
  file="$(dybatpho::path_join "${HOME}" ".gemini" "settings.json")"
  # dyshellint disable=SC2016 "$schema" is a literal JSON key, not a variable
  expr='.["$schema"] = "https://raw.githubusercontent.com/google-gemini/gemini-cli/main/schemas/settings.schema.json"'
  # AGENTS.md first, so a project written for every agent is read like Claude reads it.
  expr+=' | .context.fileName = ["AGENTS.md", "GEMINI.md"]'
  # Checkpoints make every edit undoable with /restore.
  expr+=' | .general.checkpointing.enabled = true'
  expr+=' | .privacy.usageStatisticsEnabled = false | .telemetry.enabled = false'
  # Even a stray --yolo cannot get past the dyai policy prompts.
  expr+=' | .security.disableYoloMode = true'
  dyai::json_set "${file}" "${expr}"
}

#######################################
# @description Translate global.policy.approval into each agent that has a clean edits-only preset
# @noargs
#######################################
function dyai::setup_policy {
  local approval file
  # shellcheck disable=SC2312 # a bad config read yields an empty string, a safe no-op
  approval="$(dyai::config_json '.global.policy.approval // ""' | jq -r .)"
  [[ "${approval}" == "accept-edits" ]] || return 0
  if dybatpho::is command gemini; then
    file="$(dybatpho::path_join "${HOME}" ".gemini" "settings.json")"
    dyai::json_set "${file}" '.general.defaultApprovalMode = "auto_edit"'
  fi
  if dybatpho::is command opencode; then
    file="${OPENCODE_CONFIG:-$(dybatpho::path_join "${HOME}" ".config" "opencode" "opencode.json")}"
    # Once setup_permissions turns edit into a glob map, the default is its "*".
    dyai::json_set "${file}" '.permission.edit |=
      if type == "object" then .["*"] = "allow" else "allow" end'
  fi
  if dybatpho::is command codex; then
    # Nearest Codex match: edits inside the workspace, asking before escalation.
    # Values the user already set win. The keys go first: yq writes keys in
    # order, and a scalar after a [[table]] header would land inside it.
    local chome
    chome="${CODEX_HOME:-$(dybatpho::path_join "${HOME}" ".codex")}"
    file="$(dybatpho::path_join "${chome}" "config.toml")"
    dybatpho::is dir "${chome}" || mkdir -p "${chome}"
    dybatpho::is file "${file}" || : > "${file}"
    yq -p=toml -o=toml -i '{"sandbox_mode": "workspace-write",
      "approval_policy": "on-request"} * .' "${file}" \
      || dybatpho::warn "Could not write approval policy into ${file}"
  fi
  # copilot and agy have no edits-only approval preset; left to the user.
}

#######################################
# @description Translate the shell and path rules of global.policy.permissions into every other agent
# @noargs
#######################################
function dyai::setup_permissions {
  local perms file
  perms="$(dyai::config_json '.global.policy.permissions // {}')"
  # shellcheck disable=SC2312 # a bad config read is treated as no rule at all
  jq -e 'type == "object" and ((.ask // []) + (.deny // []) | length) > 0' <<< "${perms}" > /dev/null \
    || return 0
  if dybatpho::is command opencode; then
    file="${OPENCODE_CONFIG:-$(dybatpho::path_join "${HOME}" ".config" "opencode" "opencode.json")}"
    dyai::permissions_opencode "${file}" "${perms}"
  fi
  if dybatpho::is command agy; then
    file="$(dybatpho::path_join "${HOME}" ".gemini" "antigravity-cli" "settings.json")"
    dyai::permissions_agy "${file}" "${perms}"
  fi
  if dybatpho::is command gemini; then
    file="$(dybatpho::path_join "${HOME}" ".gemini" "policies" "dyai.toml")"
    dyai::permissions_gemini "${file}" "${perms}"
  fi
  if dybatpho::is command codex; then
    local chome
    chome="${CODEX_HOME:-$(dybatpho::path_join "${HOME}" ".codex")}"
    file="$(dybatpho::path_join "${chome}" "rules" "dyai.rules")"
    dyai::permissions_codex "${file}" "${perms}"
  fi
  if dybatpho::is command hermes; then
    file="$(dybatpho::path_join "${HOME}" ".hermes" "config.yaml")"
    dyai::permissions_hermes "${file}" "${perms}"
  fi
  # Copilot CLI has no user-level config key for denied tools, only the
  # --deny-tool flag and preToolUse hooks; left to the user.
}

#######################################
# @description Merge the permission rules into opencode's permission block
# @arg $1 string Path of opencode.json
# @arg $2 string global.policy.permissions as JSON
#######################################
function dyai::permissions_opencode {
  local file perms
  dybatpho::expect_args file perms -- "$@"
  # opencode matches globs where `*` spans any characters, `/` included, and
  # the last matching key wins. A scalar value becomes the "*" default and is
  # kept first, so these narrower keys still override it.
  # dyshellint disable=SC2016 a jq program; its $names are jq variables
  dyai::json_set "${file}" "${DYAI_PERM_JQ}"'
    def glob: sub("^\\*\\*/"; "*") | sub("/\\*\\*$"; "/*") | gsub("\\*\\*"; "*");
    def keys_of: if .glued then [.p + "*"] else [.p, .p + " *"] end;
    def base: if type == "object" then . elif type == "string" then {"*": .} else {} end;
    def put($rules): reduce $rules[] as [$k, $v] (base; .[$k] = $v);
    ($perms | [(cmds("ask")[] | keys_of[] | [., "ask"]), (cmds("deny")[] | keys_of[] | [., "deny"])]) as $bash
    | ($perms | [(paths("ask"; "Read")[] | [glob, "ask"]), (paths("deny"; "Read")[] | [glob, "deny"])]) as $read
    | ($perms | [(paths("ask"; "Edit")[] | [glob, "ask"]), (paths("deny"; "Edit")[] | [glob, "deny"])]) as $edit
    | .permission = (.permission // {})
    | if ($bash | length) > 0 then .permission.bash |= put($bash) else . end
    | if ($read | length) > 0 then .permission.read |= put($read) else . end
    | if ($edit | length) > 0 then .permission.edit |= put($edit) else . end' \
    --argjson perms "${perms}"
}

#######################################
# @description Warn about the shell rules an agent's matcher cannot carry over faithfully
# @arg $1 string Agent name, for the message
# @arg $2 string global.policy.permissions as JSON
# @arg $3 bool true when the agent matches whole words, so a glued `p*` narrows to `p`
#######################################
function dyai::permission_caveats {
  local agent perms whole_words
  dybatpho::expect_args agent perms whole_words -- "$@"
  local kind p glued
  # shellcheck disable=SC2312 # jq lists the rules; a bad read lists none
  while IFS=$'\t' read -r kind p glued; do
    [[ -n "${p}" ]] || continue
    if [[ "${p}" == *'*'* ]]; then
      dybatpho::warn "${agent}: ${kind} rule \"${p}\" has an inner *, which ${agent} cannot match; not translated"
    elif [[ "${glued}" == "true" && "${whole_words}" == "true" ]]; then
      dybatpho::warn "${agent}: ${kind} rule \"${p}*\" matches whole words there, so it no longer covers \"${p}<more>\""
    fi
  done < <(jq -r "${DYAI_PERM_JQ}"'
    (cmds("deny")[] | ["deny", .p, .glued]), (cmds("ask")[] | ["ask", .p, .glued]) | @tsv' <<< "${perms}")
}

#######################################
# @description Merge the shell rules into Antigravity's global permissions
# @arg $1 string Path of ~/.gemini/antigravity-cli/settings.json
# @arg $2 string global.policy.permissions as JSON
#######################################
function dyai::permissions_agy {
  local file perms
  dybatpho::expect_args file perms -- "$@"
  # `command(<prefix>)` matches whole words, so it already covers both the
  # bare command and any arguments after it. read_file rules take absolute
  # paths, with no documented glob support, so the path rules stay out.
  dyai::permission_caveats agy "${perms}" true
  # dyshellint disable=SC2016 a jq program; its $names are jq variables
  dyai::json_set "${file}" "${DYAI_PERM_JQ}"'
    def rules($kind): $perms | cmds($kind) | map(select(literal) | "command(" + .p + ")");
    rules("ask") as $ask | rules("deny") as $deny
    | .permissions = (.permissions // {})
    | if ($ask | length) > 0 then .permissions.ask = ((.permissions.ask // []) + $ask | unique) else . end
    | if ($deny | length) > 0 then .permissions.deny = ((.permissions.deny // []) + $deny | unique) else . end' \
    --argjson perms "${perms}"
}

#######################################
# @description Write a file dyai owns whole, only when its content changed
# @arg $1 string Path of the file
# @arg $2 string Wanted content
#######################################
function dyai::write_owned {
  local file content
  dybatpho::expect_args file content -- "$@"
  local dir tmp
  if dybatpho::is file "${file}" && [[ "$(< "${file}")" == "${content}" ]]; then
    dybatpho::debug "${file} already up to date"
    return 0
  fi
  dir="$(dirname "${file}")"
  dybatpho::is dir "${dir}" || mkdir -p "${dir}"
  dybatpho::create_temp tmp "txt" "dyai" "${dir}"
  if printf '%s\n' "${content}" > "${tmp}" && mv "${tmp}" "${file}"; then
    dybatpho::info "Wrote ${file}"
  else
    dybatpho::warn "Could not write ${file}"
  fi
}

#######################################
# @description Write the shell rules as a Gemini CLI policy file owned by dyai
# @arg $1 string Path of ~/.gemini/policies/dyai.toml
# @arg $2 string global.policy.permissions as JSON
#######################################
function dyai::permissions_gemini {
  local file perms
  dybatpho::expect_args file perms -- "$@"
  local content
  # commandPrefix is a plain starts-with test, so `git push` also covers
  # `git push origin main`. Deny outranks ask by priority. A JSON string is a
  # valid TOML basic string, so tojson quotes each prefix.
  dyai::permission_caveats gemini "${perms}" false
  content="$(jq -r "${DYAI_PERM_JQ}"'
    def rule($kind; $decision; $priority):
      cmds($kind) | map(select(literal) | .p) as $p
      | if ($p | length) == 0 then empty else
          "[[rule]]\ntoolName = \"run_shell_command\"\ncommandPrefix = ["
          + ($p | map(tojson) | join(", ")) + "]\ndecision = \"" + $decision
          + "\"\npriority = " + ($priority | tostring) + "\n"
        end;
    "# Managed by dyai from global.policy.permissions; local edits are overwritten.\n"
    + ([rule("deny"; "deny"; 900), rule("ask"; "ask_user"; 800)] | join("\n"))' <<< "${perms}")"
  dyai::write_owned "${file}" "${content}"
}

#######################################
# @description Write the shell rules as a Codex execpolicy rules file owned by dyai
# @arg $1 string Path of ~/.codex/rules/dyai.rules
# @arg $2 string global.policy.permissions as JSON
#######################################
function dyai::permissions_codex {
  local file perms
  dybatpho::expect_args file perms -- "$@"
  local content
  # A pattern is a token prefix of the command's argv, so the prefix is split
  # on spaces. Codex applies the strictest matching decision.
  dyai::permission_caveats codex "${perms}" true
  content="$(jq -r "${DYAI_PERM_JQ}"'
    def rules($kind; $decision):
      cmds($kind)[] | select(literal) | "prefix_rule(pattern = " + (.p | split(" ") | map(select(. != "")) | tojson)
        + ", decision = \"" + $decision + "\", justification = \"dyai global.policy.permissions\")";
    "# Managed by dyai from global.policy.permissions; local edits are overwritten.\n"
    + ([rules("deny"; "forbidden"), rules("ask"; "prompt")] | join("\n"))' <<< "${perms}")"
  dyai::write_owned "${file}" "${content}"
}

#######################################
# @description Merge the deny shell rules into Hermes' approvals.deny list
# @arg $1 string Path of ~/.hermes/config.yaml
# @arg $2 string global.policy.permissions as JSON
#######################################
function dyai::permissions_hermes {
  local file perms
  dybatpho::expect_args file perms -- "$@"
  local globs current want dir
  # Hermes matches fnmatch globs and has no per-command ask list (its approval
  # mode decides what prompts), so only the deny rules translate.
  globs="$(jq -c "${DYAI_PERM_JQ}"'
    [cmds("deny")[] | if .glued then .p + "*" else (.p, .p + " *") end]' <<< "${perms}")"
  [[ "${globs}" != "[]" ]] || return 0
  dir="$(dirname "${file}")"
  dybatpho::is dir "${dir}" || mkdir -p "${dir}"
  dybatpho::is file "${file}" || : > "${file}"
  # shellcheck disable=SC2312 # a malformed file reads as no rule, forcing a rewrite attempt
  current="$(yq -o=json -I=0 '.approvals.deny // []' "${file}" 2> /dev/null || echo '[]')"
  current="$(jq -c 'unique' <<< "${current}")"
  want="$(jq -c --argjson g "${globs}" '. + $g | unique' <<< "${current}")"
  if [[ "${current}" == "${want}" ]]; then
    dybatpho::debug "Hermes deny rules already set in ${file}"
    return 0
  fi
  if W="${want}" yq -i '.approvals.deny = (strenv(W) | fromjson)' "${file}"; then
    dybatpho::info "Wrote deny rules into ${file}"
  else
    dybatpho::warn "Could not write deny rules into ${file}"
  fi
}

#######################################
# @description Write the notify hooks into gemini's settings.json (merge-safe, name-tagged)
# @arg $1 string Command to run on stop
# @arg $2 string Command to run when waiting for input
#######################################
function dyai::hooks_gemini {
  local stop input
  dybatpho::expect_args stop input -- "$@"
  local file expr
  file="$(dybatpho::path_join "${HOME}" ".gemini" "settings.json")"
  # AfterAgent fires once per turn, like Claude's Stop; SessionEnd, which
  # earlier versions used, only fires on exit, so drop the old entry there.
  expr='.hooks.SessionEnd |= ((. // []) | map(select(.hooks[0].name != "dyai-notify")))'
  expr+=' | if .hooks.SessionEnd == [] then del(.hooks.SessionEnd) else . end'
  expr+=' | .hooks.AfterAgent = (((.hooks.AfterAgent // []) | map(select(.hooks[0].name != "dyai-notify")))'
  # shellcheck disable=SC2016 # $s is a jq --arg variable, expanded by jq, not the shell
  expr+=' + [{hooks: [{type: "command", command: $s, name: "dyai-notify"}]}])'
  expr+=' | .hooks.Notification = (((.hooks.Notification // []) | map(select(.hooks[0].name != "dyai-notify")))'
  # shellcheck disable=SC2016 # $i is a jq --arg variable, expanded by jq, not the shell
  expr+=' + [{hooks: [{type: "command", command: $i, name: "dyai-notify"}]}])'
  dyai::json_set "${file}" "${expr}" --arg s "${stop}" --arg i "${input}"
}

#######################################
# @description Write the notify hooks into Copilot's own dyai hooks file
# @arg $1 string Command to run on stop
# @arg $2 string Command to run when waiting for input
#######################################
function dyai::hooks_copilot {
  local stop input
  dybatpho::expect_args stop input -- "$@"
  local chome file expr
  chome="${COPILOT_HOME:-$(dybatpho::path_join "${HOME}" ".copilot")}"
  file="$(dybatpho::path_join "${chome}" "hooks" "dyai.json")"
  expr='.version = 1'
  # shellcheck disable=SC2016 # $s is a jq --arg variable, expanded by jq, not the shell
  expr+=' | .hooks.agentStop = [{type: "command", bash: $s}]'
  # shellcheck disable=SC2016 # $i is a jq --arg variable, expanded by jq, not the shell
  expr+=' | .hooks.notification = [{type: "command", bash: $i}]'
  dyai::json_set "${file}" "${expr}" --arg s "${stop}" --arg i "${input}"
}

#######################################
# @description Write the notify hooks into Codex's config.toml, idempotently
# @arg $1 string Command to run on stop
# @arg $2 string Command to run when waiting for input
#######################################
function dyai::hooks_codex {
  local stop input
  dybatpho::expect_args stop input -- "$@"
  local chome file cur_stop cur_input
  chome="${CODEX_HOME:-$(dybatpho::path_join "${HOME}" ".codex")}"
  file="$(dybatpho::path_join "${chome}" "config.toml")"
  dybatpho::is dir "${chome}" || mkdir -p "${chome}"
  dybatpho::is file "${file}" || : > "${file}"
  # shellcheck disable=SC2312 # a read error on a malformed file just forces a rewrite
  cur_stop="$(yq -p=toml -o=json -I=0 '.hooks.Stop[0].hooks[0].command // ""' \
    "${file}" 2> /dev/null || echo '""')"
  # shellcheck disable=SC2312 # a read error on a malformed file just forces a rewrite
  cur_input="$(yq -p=toml -o=json -I=0 '.hooks.PermissionRequest[0].hooks[0].command // ""' \
    "${file}" 2> /dev/null || echo '""')"
  if [[ "${cur_stop}" == "\"${stop}\"" && "${cur_input}" == "\"${input}\"" ]]; then
    dybatpho::debug "Codex notify hooks already set in ${file}"
    return 0
  fi
  # Each event is a list of matcher groups whose handlers need a type; Codex has
  # no Notification event, so waiting for input is its PermissionRequest.
  if S="${stop}" I="${input}" yq -p=toml -o=toml -i \
    '.hooks.Stop = [{"hooks": [{"type": "command", "command": strenv(S)}]}]
     | .hooks.PermissionRequest = [{"hooks": [{"type": "command", "command": strenv(I)}]}]
     | del(.hooks.Notification)' "${file}"; then
    dybatpho::info "Wrote notify hooks into ${file}"
  else
    dybatpho::warn "Could not write notify hooks into ${file}"
  fi
}

#######################################
# @description Translate global.hooks (stop/input) into each hook-capable agent
# @noargs
#######################################
function dyai::setup_hooks {
  local stop input
  # shellcheck disable=SC2312 # a bad config read yields an empty string, a safe no-op
  stop="$(dyai::config_json '.global.hooks.stop.run // ""' | jq -r .)"
  # shellcheck disable=SC2312 # a bad config read yields an empty string, a safe no-op
  input="$(dyai::config_json '.global.hooks.input.run // ""' | jq -r .)"
  [[ -n "${stop}" || -n "${input}" ]] || return 0
  if dybatpho::is command gemini; then dyai::hooks_gemini "${stop}" "${input}"; fi
  if dybatpho::is command copilot; then dyai::hooks_copilot "${stop}" "${input}"; fi
  if dybatpho::is command codex; then dyai::hooks_codex "${stop}" "${input}"; fi
  # agy's hooks.json schema is undocumented and opencode has no config hooks; both skipped.
}

#######################################
# @description Entrypoint
# @noargs

#######################################
# @description Fetch a GitHub repo at a pinned ref into an XDG cache, reusing it
# @arg $1 string owner/repo
# @arg $2 string commit SHA or tag (never a moving branch)
# @stdout The path of the extracted checkout
# @exitcode 1 The download failed
#######################################
function dyai::fetch_repo {
  local repo ref
  dybatpho::expect_args repo ref -- "$@"
  local cache tmp extracted
  cache="$(dybatpho::path_join "${HOME}" ".cache" "dyai" "${repo//\//-}-${ref}")"
  if ! dybatpho::is dir "${cache}"; then
    dybatpho::create_temp tmp "/" "dyai-fetch"
    # shellcheck disable=SC2312 # a failed download warns and returns, not aborts
    if ! curl -fsSL --connect-timeout 30 --max-time 300 \
      "https://github.com/${repo}/archive/${ref}.tar.gz" | tar -xz -C "${tmp}"; then
      dybatpho::warn "Could not fetch ${repo}@${ref}"
      return 1
    fi
    # The tarball extracts to a single <reponame>-<ref> directory.
    # shellcheck disable=SC2312 # the find yields exactly the one extracted dir
    extracted="$(find "${tmp}" -mindepth 1 -maxdepth 1 -type d | head -1)"
    dybatpho::ensure_dir "$(dirname "${cache}")" > /dev/null
    mv "${extracted}" "${cache}"
  fi
  printf '%s' "${cache}"
}

#######################################
# @description Install the subagents in global.subagents into Claude's agents dir
# @noargs
#######################################
function dyai::setup_subagents {
  # The VoltAgent subagents are Claude-format; other agents' formats differ.
  dybatpho::is command claude || return 0
  local sources agents_dir
  sources="$(dyai::config_json '.global.subagents // []')"
  agents_dir="$(dybatpho::path_join "${HOME}" ".claude" "agents")"
  local count i repo ref src incl excl md name dest leaf
  local -a mds
  count="$(jq 'length' <<< "${sources}")"
  for ((i = 0; i < count; i++)); do
    repo="$(jq -r --argjson i "${i}" '.[$i].repo' <<< "${sources}")"
    ref="$(jq -r --argjson i "${i}" '.[$i].ref' <<< "${sources}")"
    # shellcheck disable=SC2310 # a failed fetch warns inside and we skip this source
    src="$(dyai::fetch_repo "${repo}" "${ref}")" || continue
    # Leaf names kept out of the global install (they can still be pulled per
    # project by a preset, which resolves subagents across the whole tree).
    excl="$(jq -c --argjson i "${i}" '.[$i].exclude // []' <<< "${sources}")"
    dybatpho::ensure_dir "${agents_dir}" > /dev/null
    # shellcheck disable=SC2312 # the include list comes from the config we just read
    while IFS= read -r incl; do
      [[ -n "${incl}" ]] || continue
      # An include entry is a single .md file, or a directory of them.
      if [[ "${incl}" == *.md ]]; then
        mds=("${src}/${incl}")
      else
        mds=()
        # shellcheck disable=SC2312 # find lists the dir's .md files, a bad path lists none
        while IFS= read -r md; do mds+=("${md}"); done \
          < <(find "${src}/${incl}" -mindepth 1 -maxdepth 1 -name '*.md' 2> /dev/null)
      fi
      for md in "${mds[@]+"${mds[@]}"}"; do
        dybatpho::is file "${md}" || continue
        name="$(basename "${md}")"
        [[ "${name}" == "README.md" ]] && continue
        leaf="${name%.md}"
        # shellcheck disable=SC2312 # jq membership test; a bad read is false
        if jq -e --arg n "${leaf}" 'index($n) != null' <<< "${excl}" > /dev/null; then
          dybatpho::debug "subagent ${leaf} excluded from the global baseline"
          continue
        fi
        dest="$(dybatpho::path_join "${agents_dir}" "${name}")"
        if ! dybatpho::is file "${dest}" || ! cmp -s "${md}" "${dest}"; then
          if cp -- "${md}" "${dest}"; then
            dybatpho::info "Installed subagent ${leaf}"
          else
            dybatpho::warn "Could not install subagent ${name}"
          fi
        fi
      done
    done < <(jq -r --argjson i "${i}" '.[$i].include[]' <<< "${sources}")
  done
}

#######################################
# @description Resolve a preset name to its registry section, or die
# @arg $1 string Preset name
# @stdout The section (languages|infra|presets)
#######################################
function dyai::resolve_preset {
  local name
  dybatpho::expect_args name -- "$@"
  local section found=""
  for section in languages infra presets; do
    # shellcheck disable=SC2312 # config_json yields true/false; a missing section is false
    if dyai::config_json ".registry.${section} // {} | has(\"${name}\")" | grep -qx true; then
      [[ -z "${found}" ]] || dybatpho::die "preset ${name} is ambiguous (in ${found} and ${section})"
      found="${section}"
    fi
  done
  [[ -n "${found}" ]] || dybatpho::die "unknown preset: ${name}"
  printf '%s' "${found}"
}

#######################################
# @description Resolve this repo's personal ignore file (works in a worktree, where .git is a file)
# @arg $1 string The project root
# @stdout Absolute path of info/exclude
# @exitcode 1 Not a git repository
#######################################
function dyai::git_exclude {
  local root gp
  dybatpho::expect_args root -- "$@"
  gp="$(git -C "${root}" rev-parse --git-path info/exclude 2> /dev/null)" || return 1
  case "${gp}" in
    /*) printf '%s' "${gp}" ;;
    *) printf '%s/%s' "${root}" "${gp}" ;;
  esac
}

#######################################
# @description Add a repo-root-anchored pattern to the personal ignore if absent
# @arg $1 string info/exclude path
# @arg $2 string Pattern, already anchored as the caller wants it
#######################################
function dyai::exclude_add {
  local exclude pattern
  dybatpho::expect_args exclude pattern -- "$@"
  # Some git versions do not create .git/info on init, so the append target's
  # parent may be missing; create it before writing.
  dybatpho::ensure_dir "$(dirname "${exclude}")" > /dev/null
  grep -qxF -- "${pattern}" "${exclude}" 2> /dev/null && return 0
  printf '%s\n' "${pattern}" >> "${exclude}" || dybatpho::die "cannot write ${exclude}"
}

#######################################
# @description Opt the current project into a registry preset (records only; see materialize)
# @arg $1 string Preset name
#######################################
function dyai::use {
  local name
  dybatpho::expect_args name -- "$@"
  CONFIG_FILE="${CONFIG_FILE:-$(dybatpho::path_join "${HOME}" ".config" "dyai" "config.yaml")}"
  local root
  root="$(git rev-parse --show-toplevel 2> /dev/null)" \
    || dybatpho::die "dyai use must run inside a git repository"
  # shellcheck disable=SC2310 # resolve_preset dies on unknown/ambiguous, which is what we want
  dyai::resolve_preset "${name}" > /dev/null
  local toml="${root}/.dyai.toml"
  dybatpho::is file "${toml}" || : > "${toml}"
  # shellcheck disable=SC2312 # a missing use list greps to nothing, so we add it
  if ! yq -p=toml '.use[]' "${toml}" 2> /dev/null | grep -qxF -- "${name}"; then
    N="${name}" yq -p=toml -o=toml -i '.use = ((.use // []) + [strenv(N)])' "${toml}"
  fi
  local exclude
  # .git is a file in a linked worktree, so the exclude path is resolved, not built.
  exclude="$(dyai::git_exclude "${root}")" || dybatpho::die "cannot locate the git exclude file"
  dyai::exclude_add "${exclude}" '/.dyai.toml'
  dybatpho::info "Project uses preset ${name}"
  dyai::materialize
}

#######################################
# @description Prune manifest paths no longer wanted, then record the new manifest
# @arg $1 string Path of the project .dyai.toml
# @arg $@ string The desired materialized paths
#######################################
function dyai::prune_and_record {
  local toml
  dybatpho::expect_args toml -- "$@"
  shift
  local root desired_nl old list
  root="$(dirname "${toml}")"
  desired_nl="$(printf '%s\n' "$@")"
  # shellcheck disable=SC2312 # a missing manifest lists nothing, so nothing is pruned
  while IFS= read -r old; do
    [[ -n "${old}" ]] || continue
    # .dyai.toml is an on-disk file; a crafted or corrupt manifest must never
    # turn this prune into an arbitrary recursive delete. Reject any entry
    # with a traversal segment, and confine deletion to the two subtrees
    # materialize actually writes — a prefix glob alone would let `${root}/..`
    # match, so the allow-list is on the literal subtree paths.
    case "${old}" in
      *'/../'* | *'/./'* | */.. | */.) continue ;;
      "${root}/.claude/agents/"* | "${root}/.claude/commands/"* | "${root}/.agents/skills/"*) ;;
      *) continue ;;
    esac
    grep -qxF -- "${old}" <<< "${desired_nl}" || rm -rf -- "${old}"
  done < <(yq -p=toml '.materialized[]?' "${toml}" 2> /dev/null)
  # shellcheck disable=SC2312 # the desired list is dyai-built project paths
  list="$(printf '%s\n' "$@" | sort -u | jq -R . | jq -cs 'map(select(. != ""))')"
  LIST="${list}" yq -p=toml -o=toml -i '.materialized = (strenv(LIST) | fromjson)' "${toml}"
  # Every materialized file is PERSONAL too, so anchor each into the personal
  # ignore. Stale entries for removed files are harmless, so we only ever add.
  local exclude p
  # shellcheck disable=SC2310 # outside a repo there is nothing to personal-ignore
  exclude="$(dyai::git_exclude "${root}")" || return 0
  for p in "$@"; do
    [[ -n "${p}" && "${p}" == "${root}"/* ]] || continue
    dyai::exclude_add "${exclude}" "/${p#"${root}/"}"
  done
}

#######################################
# @description Materialize every preset in ./.dyai.toml into the project-scope config
# @noargs
#######################################
function dyai::materialize {
  local root toml
  root="$(git rev-parse --show-toplevel 2> /dev/null)" || return 0
  toml="${root}/.dyai.toml"
  dybatpho::is file "${toml}" || return 0
  CONFIG_FILE="${CONFIG_FILE:-$(dybatpho::path_join "${HOME}" ".config" "dyai" "config.yaml")}"
  local agents_dir="${root}/.claude/agents" commands_dir="${root}/.claude/commands"
  local sa_json repo ref src cmd_json crepo cref csrc
  sa_json="$(dyai::config_json '.global.subagents[0] // {}')"
  repo="$(jq -r '.repo // ""' <<< "${sa_json}")"
  ref="$(jq -r '.ref // ""' <<< "${sa_json}")"
  src=""
  # shellcheck disable=SC2310 # a failed fetch leaves src empty and subagents are skipped
  [[ -z "${repo}" ]] || src="$(dyai::fetch_repo "${repo}" "${ref}")" || src=""
  # Commands resolve from their own pinned source, the same way subagents do.
  cmd_json="$(dyai::config_json '.global.commands[0] // {}')"
  crepo="$(jq -r '.repo // ""' <<< "${cmd_json}")"
  cref="$(jq -r '.ref // ""' <<< "${cmd_json}")"
  csrc=""
  # shellcheck disable=SC2310 # a failed fetch leaves csrc empty and commands are skipped
  [[ -z "${crepo}" ]] || csrc="$(dyai::fetch_repo "${crepo}" "${cref}")" || csrc=""
  local -a desired=() desired_mcp=() registered_mcp=()
  local preset section pj sa_count sa md dest sk leaf incomplete="" mcpname mdef cmd_count cmdname
  # Servers already registered project-local, so a re-run does not re-add them.
  local existing_mcp
  # shellcheck disable=SC2312 # a missing manifest reads as an empty list
  existing_mcp="$(yq -p=toml -o=json -I=0 '.materialized_mcp // []' "${toml}" 2> /dev/null || echo '[]')"
  # shellcheck disable=SC2312 # the use list comes from the project .dyai.toml
  while IFS= read -r preset; do
    [[ -n "${preset}" ]] || continue
    # shellcheck disable=SC2312 # a stale/unknown entry warns and is skipped, not fatal
    section="$(dyai::resolve_preset "${preset}" 2> /dev/null)" \
      || {
        dybatpho::warn "unknown preset ${preset} in .dyai.toml, skip"
        continue
      }
    pj="$(dyai::config_json ".registry.${section}.\"${preset}\"")"
    # shellcheck disable=SC2312 # jq yields a count; a bad read is 0, which is safe
    sa_count="$(jq -r '.subagents // [] | length' <<< "${pj}")"
    if [[ -n "${src}" ]]; then
      # shellcheck disable=SC2312 # jq lists the preset's subagent names
      while IFS= read -r sa; do
        [[ -n "${sa}" ]] || continue
        # The subagent name is unique in the source; find it anywhere under it.
        # shellcheck disable=SC2312 # find locates the one named subagent .md
        md="$(find "${src}" -type f -name "${sa}.md" 2> /dev/null | head -1)"
        if [[ -z "${md}" ]]; then
          dybatpho::warn "subagent ${sa} not found in ${repo}"
          continue
        fi
        dybatpho::ensure_dir "${agents_dir}" > /dev/null
        dest="${agents_dir}/${sa}.md"
        if ! { dybatpho::is file "${dest}" && cmp -s "${md}" "${dest}"; }; then
          cp -- "${md}" "${dest}"
        fi
        desired+=("${dest}")
      done < <(jq -r '.subagents[]?' <<< "${pj}")
    # A configured source whose fetch failed leaves src empty. If this preset
    # wants subagents, the desired set is now incomplete — pruning against it
    # would delete the subagents of presets we never got to. Flag it and refuse
    # to prune. An empty repo means no source is configured at all, not a
    # transient failure, so it does not block the prune.
    elif [[ -n "${repo}" && "${sa_count}" != "0" ]]; then
      incomplete=1
    fi
    # Commands → ./.claude/commands/<name>.md, resolved from the commands source.
    # shellcheck disable=SC2312 # jq yields a count; a bad read is 0, which is safe
    cmd_count="$(jq -r '.commands // [] | length' <<< "${pj}")"
    if [[ -n "${csrc}" ]]; then
      # shellcheck disable=SC2312 # jq lists the preset's command names
      while IFS= read -r cmdname; do
        [[ -n "${cmdname}" ]] || continue
        # shellcheck disable=SC2312 # find locates the one named command .md
        md="$(find "${csrc}" -type f -name "${cmdname}.md" 2> /dev/null | head -1)"
        if [[ -z "${md}" ]]; then
          dybatpho::warn "command ${cmdname} not found in ${crepo}"
          continue
        fi
        dybatpho::ensure_dir "${commands_dir}" > /dev/null
        dest="${commands_dir}/${cmdname}.md"
        if ! { dybatpho::is file "${dest}" && cmp -s "${md}" "${dest}"; }; then
          cp -- "${md}" "${dest}"
        fi
        desired+=("${dest}")
      done < <(jq -r '.commands[]?' <<< "${pj}")
    elif [[ -n "${crepo}" && "${cmd_count}" != "0" ]]; then
      incomplete=1
    fi
    # shellcheck disable=SC2312 # jq lists the preset's skills
    while IFS= read -r sk; do
      [[ -n "${sk}" ]] || continue
      # owner/repo@name, or a pinned GitHub tree URL ending in the skill dir;
      # the skills CLI installs either under its lowercased name.
      leaf="${sk##*@}"
      leaf="${leaf##*/}"
      leaf="${leaf,,}"
      if dybatpho::is dir "${root}/.agents/skills/${leaf}"; then
        dybatpho::debug "skill ${leaf} already installed in project"
      else
        # The skills CLI drains stdin, which here is the rest of the skill list.
        (cd "${root}" && bunx "${SKILLS_CLI}" add "${sk}" -y &> /dev/null < /dev/null) \
          || dybatpho::warn "Could not install skill ${sk}"
      fi
      desired+=("${root}/.agents/skills/${leaf}")
    done < <(jq -r '.skills[]?' <<< "${pj}")
    # MCP servers register in Claude's project-LOCAL scope (private to this
    # project, kept in ~/.claude.json, not in the shared ./.mcp.json), so a
    # teammate never inherits a personal preset choice.
    # shellcheck disable=SC2312 # jq lists the preset's mcp server names
    while IFS= read -r mcpname; do
      [[ -n "${mcpname}" ]] || continue
      # `desired_mcp` is what the project wants (drives pruning); `registered_mcp`
      # is what is actually registered now (becomes the manifest), so a failed or
      # claude-absent registration is NOT recorded and is retried next run.
      desired_mcp+=("${mcpname}")
      dybatpho::is command claude || continue
      # shellcheck disable=SC2312 # already registered (in the manifest) → keep, no churn
      if jq -e --arg n "${mcpname}" 'index($n) != null' <<< "${existing_mcp}" > /dev/null; then
        dybatpho::debug "MCP ${mcpname} already registered for this project"
        registered_mcp+=("${mcpname}")
        continue
      fi
      mdef="$(jq -c --arg n "${mcpname}" \
        '.mcp[$n] | {type: "stdio", command: .command, args: (.args // []), env: (.env // {})}' <<< "${pj}")"
      if (cd "${root}" && claude mcp add-json --scope local "${mcpname}" "${mdef}" > /dev/null < /dev/null); then
        registered_mcp+=("${mcpname}")
      else
        dybatpho::warn "Could not register MCP ${mcpname} for this project"
      fi
    done < <(jq -r '.mcp // {} | keys[]?' <<< "${pj}")
  done < <(yq -p=toml '.use[]' "${toml}" 2> /dev/null)
  if [[ -n "${incomplete}" ]]; then
    dybatpho::die "could not fetch a subagent/command source; project left unchanged"
  fi
  dyai::prune_and_record "${toml}" "${desired[@]+"${desired[@]}"}"
  local desired_mcp_json registered_mcp_json
  desired_mcp_json="$(dyai::names_to_json "${desired_mcp[@]+"${desired_mcp[@]}"}")"
  registered_mcp_json="$(dyai::names_to_json "${registered_mcp[@]+"${registered_mcp[@]}"}")"
  dyai::reconcile_mcp "${toml}" "${root}" "${desired_mcp_json}" "${registered_mcp_json}"
}

#######################################
# @description Encode the given names as a compact JSON array of unique non-empty strings
# @arg $@ string Names (may be none)
# @stdout A JSON array
#######################################
function dyai::names_to_json {
  # shellcheck disable=SC2312 # printf cannot meaningfully fail; jq is the gate
  printf '%s\n' "$@" | jq -R . | jq -cs 'map(select(. != ""))'
}

#######################################
# @description Unregister project-local MCP servers no longer wanted, then record what is registered
# @arg $1 string Path of the project .dyai.toml
# @arg $2 string The project root
# @arg $3 string JSON array of DESIRED server names (what the project wants) — drives pruning
# @arg $4 string JSON array of REGISTERED server names (what is actually registered) — the manifest
#######################################
function dyai::reconcile_mcp {
  local toml root desired_json registered_json
  dybatpho::expect_args toml root desired_json registered_json -- "$@"
  local old
  if dybatpho::is command claude; then
    # Remove a previously-registered server only when it is no longer desired —
    # never because a (still-wanted) registration failed this run.
    # shellcheck disable=SC2312 # a missing manifest lists nothing, so nothing is pruned
    while IFS= read -r old; do
      [[ -n "${old}" ]] || continue
      # shellcheck disable=SC2312 # membership test; a still-desired server is kept
      jq -e --arg n "${old}" 'index($n) != null' <<< "${desired_json}" > /dev/null && continue
      (cd "${root}" && claude mcp remove --scope local "${old}" &> /dev/null < /dev/null) \
        || dybatpho::debug "MCP ${old} was not registered, nothing to remove"
    done < <(yq -p=toml '.materialized_mcp[]?' "${toml}" 2> /dev/null)
  fi
  # The manifest records what is actually registered, so a failed/absent-claude
  # registration is retried on the next run rather than assumed done.
  local list
  list="$(jq -cS 'unique' <<< "${registered_json}")"
  LIST="${list}" yq -p=toml -o=toml -i '.materialized_mcp = (strenv(LIST) | fromjson)' "${toml}"
}

#######################################
# @description List the global baseline and this project's selected presets
# @noargs
# @stdout The baseline (skills, subagents, mcp), the registry, and the project use list
#######################################
function dyai::ls {
  CONFIG_FILE="${CONFIG_FILE:-$(dybatpho::path_join "${HOME}" ".config" "dyai" "config.yaml")}"
  dybatpho::is file "${CONFIG_FILE}" || dybatpho::die "dyai config not found: ${CONFIG_FILE}"
  local skills_n subagents mcp_names section names
  skills_n="$(dyai::config_json '.global.skills // [] | length')"
  subagents="$(dyai::config_json '.global.subagents // [] | map(.repo) | join(" ")')"
  # shellcheck disable=SC2312 # the names join to a single line; a bad read is empty
  mcp_names="$(dyai::config_json '.global.mcp // {} | keys | join(" ")')"
  printf 'Global baseline:\n'
  printf '  skills: %s\n' "${skills_n}"
  printf '  subagents: %s\n' "${subagents:-none}"
  printf '  mcp: %s\n' "${mcp_names:-none}"
  printf 'Registry presets:\n'
  for section in languages infra presets; do
    names="$(dyai::config_json ".registry.${section} // {} | keys | join(\" \")")"
    [[ -n "${names}" ]] && printf '  %s: %s\n' "${section}" "${names}"
  done
  local root toml used
  root="$(git rev-parse --show-toplevel 2> /dev/null)" || return 0
  toml="${root}/.dyai.toml"
  if dybatpho::is file "${toml}"; then
    # shellcheck disable=SC2312 # a missing use list joins to empty
    used="$(yq -p=toml -o=json -I=0 '.use // []' "${toml}" 2> /dev/null | jq -r 'join(" ")')"
  fi
  printf 'Project %s:\n' "${root}"
  printf '  use: %s\n' "${used:-none}"
}

#######################################
# @description Drop a preset from this project, prune the files it owned, re-materialize
# @arg $1 string Preset name to remove
#######################################
function dyai::rm {
  local name
  dybatpho::expect_args name -- "$@"
  local root toml
  root="$(git rev-parse --show-toplevel 2> /dev/null)" \
    || dybatpho::die "dyai rm must run inside a git repository"
  toml="${root}/.dyai.toml"
  dybatpho::is file "${toml}" || dybatpho::die "this project uses no presets"
  # shellcheck disable=SC2312 # a missing use list greps to nothing, which is "not used"
  if ! yq -p=toml '.use[]' "${toml}" 2> /dev/null | grep -qxF -- "${name}"; then
    dybatpho::die "preset ${name} is not used by this project"
  fi
  N="${name}" yq -p=toml -o=toml -i '.use = ((.use // []) | map(select(. != strenv(N))))' "${toml}"
  dybatpho::info "Project no longer uses preset ${name}"
  # Re-materialize from the remaining presets; prune_and_record removes the
  # files the dropped preset owned that no surviving preset still wants.
  dyai::materialize
}

#######################################
# @description Run each global installer once, per installed agent it targets
# @noargs
#######################################
function dyai::setup_installers {
  local installers dir name agent cmd hash marker
  installers="$(dyai::config_json '.global.installers // {}')"
  dir="$(dybatpho::path_join "${HOME}" ".cache" "dyai" "installers")"
  # shellcheck disable=SC2312 # a bad config read yields no rows, which is a safe no-op
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    # One command per agent id; run only when that agent's launcher is present.
    # shellcheck disable=SC2312 # a bad entry yields no rows, a safe no-op
    while IFS=$'\t' read -r agent cmd; do
      [[ -n "${agent}" && -n "${cmd}" ]] || continue
      dybatpho::is command "${agent}" || continue
      # Marker keyed on the command, so a changed command re-runs but a repeat
      # apply does not. The command is a trusted config string, run like a hook.
      # shellcheck disable=SC2312 # sha of the command string; a stable key
      hash="$(printf '%s' "${cmd}" | sha256sum | cut -d' ' -f1)"
      marker="$(dybatpho::path_join "${dir}" "${name}.${agent}.${hash}")"
      if dybatpho::is file "${marker}"; then
        dybatpho::debug "installer ${name} for ${agent} already run"
        continue
      fi
      dybatpho::info "Run installer ${name} for ${agent}"
      if bash -c "${cmd}" < /dev/null; then
        dybatpho::ensure_dir "${dir}" > /dev/null
        : > "${marker}"
      else
        dybatpho::warn "installer ${name} for ${agent} failed"
      fi
    done < <(jq -r --arg n "${name}" '.[$n].commands | to_entries[] | [.key, .value] | @tsv' <<< "${installers}")
  done < <(jq -r 'keys[]?' <<< "${installers}")
}

#######################################
# @description Run the global AI-agent setup from ~/.config/dyai/config.yaml
# @noargs
#######################################
function dyai::install {
  CONFIG_FILE="$(dybatpho::path_join "${HOME}" ".config" "dyai" "config.yaml")"
  PLUGINS_DIR="$(dybatpho::path_join "${HOME}" ".claude" "plugins")"
  SKILLS_DIR="$(dybatpho::path_join "${HOME}" ".agents" "skills")"
  DEFAULT_CONFIG_DIR="$(dybatpho::path_join "${HOME}" ".claude")"
  ENTERPRISE_DIR="$(dybatpho::path_join "${HOME}" "Working" "enterprise")"
  if ! dybatpho::is command jq || ! dybatpho::is command yq; then
    dybatpho::warn "jq or yq is not installed, skip setting up AI agents"
    return 0
  fi
  if ! dybatpho::is file "${CONFIG_FILE}"; then
    dybatpho::warn "dyai config not found at ${CONFIG_FILE}, skip setting up AI agents"
    return 0
  fi
  if dybatpho::is command claude; then
    dyai::setup_marketplaces
    dyai::setup_plugins
  else
    dybatpho::warn "claude is not installed, skip marketplaces and plugins"
  fi
  dyai::setup_mcp
  dyai::setup_gemini
  dyai::setup_policy
  dyai::setup_permissions
  dyai::setup_hooks
  dyai::setup_subagents
  if dybatpho::is command bunx; then
    dyai::setup_skills
  else
    dybatpho::warn "bunx is not installed, skip skills"
  fi
  dyai::setup_installers
}
