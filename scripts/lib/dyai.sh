# @file dyai.sh
# @brief Install AI-agent marketplaces, plugins, skills, MCP servers, policy and hooks
# @description The global install logic behind `dyai install` and the setup hook.
# Reads the single declarative source `~/.config/dyai/config.yaml` and brings
# every supported agent's extensions in line with it. Sourced (not executed);
# the caller sources dybatpho first and owns strict mode.
# shellcheck shell=bash

# The skills CLI is pinned, so an apply never runs a release nobody looked at.
SKILLS_CLI="skills@1.7.2"

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
    claude plugin marketplace add "${source}" || dybatpho::warn "Could not add marketplace ${name}"
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
    claude plugin install "${plugin}" || dybatpho::warn "Could not install plugin ${plugin}"
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
    bunx "${SKILLS_CLI}" add "${skill}" -g -y || dybatpho::warn "Could not install skill ${skill}"
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
# @description Register an MCP server in every Claude configuration where it is missing or differs
# @arg $1 string Name of the server
# @arg $2 string Server definition as JSON, as `claude mcp add-json` takes it
#######################################
function dyai::setup_mcp_server {
  local name definition
  dybatpho::expect_args name definition -- "$@"
  local dir state_file current wanted def_dir
  # shellcheck disable=SC2312 # the directories are globbed, the loop cannot fail on them
  while IFS= read -r dir; do
    # filesystem is scoped to the enterprise tree in an enterprise config dir,
    # so an enterprise-context agent never sees personal or community files.
    def_dir="${definition}"
    if [[ "${name}" == "filesystem" && "${dir}" == "${ENTERPRISE_DIR}"/* ]]; then
      def_dir="$(jq -c --arg d "${ENTERPRISE_DIR}" '.args = [.args[0], $d]' <<< "${definition}")"
    fi
    wanted="$(jq -cS . <<< "${def_dir}")"
    # The default configuration keeps its state next to the directory, not in it.
    if [[ "${dir}" == "${DEFAULT_CONFIG_DIR}" ]]; then
      state_file="$(dybatpho::path_join "${HOME}" ".claude.json")"
    else
      state_file="$(dybatpho::path_join "${dir}" ".claude.json")"
    fi
    current=""
    if dybatpho::is file "${state_file}"; then
      # shellcheck disable=SC2312 # a corrupt state file falls back to empty, not an abort
      current="$(jq -cS --arg name "${name}" '.mcpServers[$name] // empty' "${state_file}" 2> /dev/null || printf '')"
    fi
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
      # shellcheck disable=SC2310 # a failure only warns, the other agents still run
      dyai::setup_mcp_server "${name}" "${definition}"
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
    dyai::json_set "${file}" '.permission.edit = "allow"'
  fi
  # codex, copilot and agy have no edits-only approval preset; left to the user.
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
  expr='.hooks.SessionEnd = (((.hooks.SessionEnd // []) | map(select(.hooks[0].name != "dyai-notify")))'
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
  cur_stop="$(yq -p=toml -o=json -I=0 '.hooks.Stop.hooks[0].command // ""' \
    "${file}" 2> /dev/null || echo '""')"
  # shellcheck disable=SC2312 # a read error on a malformed file just forces a rewrite
  cur_input="$(yq -p=toml -o=json -I=0 '.hooks.Notification.hooks[0].command // ""' \
    "${file}" 2> /dev/null || echo '""')"
  if [[ "${cur_stop}" == "\"${stop}\"" && "${cur_input}" == "\"${input}\"" ]]; then
    dybatpho::debug "Codex notify hooks already set in ${file}"
    return 0
  fi
  if S="${stop}" I="${input}" yq -p=toml -o=toml -i \
    '.hooks.Stop.hooks = [{"command": strenv(S)}]
     | .hooks.Notification.hooks = [{"command": strenv(I)}]' "${file}"; then
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
  local count i repo ref src incl md name dest
  count="$(jq 'length' <<< "${sources}")"
  for ((i = 0; i < count; i++)); do
    repo="$(jq -r --argjson i "${i}" '.[$i].repo' <<< "${sources}")"
    ref="$(jq -r --argjson i "${i}" '.[$i].ref' <<< "${sources}")"
    # shellcheck disable=SC2310 # a failed fetch warns inside and we skip this source
    src="$(dyai::fetch_repo "${repo}" "${ref}")" || continue
    dybatpho::ensure_dir "${agents_dir}" > /dev/null
    # shellcheck disable=SC2312 # the include list comes from the config we just read
    while IFS= read -r incl; do
      [[ -n "${incl}" ]] || continue
      # shellcheck disable=SC2312 # find lists the category's .md files, a bad path lists none
      while IFS= read -r md; do
        name="$(basename "${md}")"
        [[ "${name}" == "README.md" ]] && continue
        dest="$(dybatpho::path_join "${agents_dir}" "${name}")"
        if ! dybatpho::is file "${dest}" || ! cmp -s "${md}" "${dest}"; then
          if cp -- "${md}" "${dest}"; then
            dybatpho::info "Installed subagent ${name%.md}"
          else
            dybatpho::warn "Could not install subagent ${name}"
          fi
        fi
      done < <(find "${src}/${incl}" -mindepth 1 -maxdepth 1 -name '*.md' 2> /dev/null)
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
  local exclude="${root}/.git/info/exclude"
  grep -qxF '.dyai.toml' "${exclude}" 2> /dev/null || printf '.dyai.toml\n' >> "${exclude}"
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
    [[ -n "${old}" && "${old}" == "${root}"/* ]] || continue
    grep -qxF -- "${old}" <<< "${desired_nl}" || rm -rf -- "${old}"
  done < <(yq -p=toml '.materialized[]?' "${toml}" 2> /dev/null)
  # shellcheck disable=SC2312 # the desired list is dyai-built project paths
  list="$(printf '%s\n' "$@" | sort -u | jq -R . | jq -cs 'map(select(. != ""))')"
  LIST="${list}" yq -p=toml -o=toml -i '.materialized = (strenv(LIST) | fromjson)' "${toml}"
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
  local agents_dir="${root}/.claude/agents"
  local sa_json repo ref src
  sa_json="$(dyai::config_json '.global.subagents[0] // {}')"
  repo="$(jq -r '.repo // ""' <<< "${sa_json}")"
  ref="$(jq -r '.ref // ""' <<< "${sa_json}")"
  src=""
  # shellcheck disable=SC2310 # a failed fetch leaves src empty and subagents are skipped
  [[ -z "${repo}" ]] || src="$(dyai::fetch_repo "${repo}" "${ref}")" || src=""
  local -a desired=()
  local preset section pj sa md dest sk leaf
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
    fi
    # shellcheck disable=SC2312 # jq lists the preset's skills
    while IFS= read -r sk; do
      [[ -n "${sk}" ]] || continue
      leaf="${sk##*@}"
      (cd "${root}" && bunx "${SKILLS_CLI}" add "${sk}" -y &> /dev/null) \
        || dybatpho::warn "Could not install skill ${sk}"
      desired+=("${root}/.agents/skills/${leaf}")
    done < <(jq -r '.skills[]?' <<< "${pj}")
  done < <(yq -p=toml '.use[]' "${toml}" 2> /dev/null)
  dyai::prune_and_record "${toml}" "${desired[@]+"${desired[@]}"}"
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
  dyai::setup_policy
  dyai::setup_hooks
  dyai::setup_subagents
  if dybatpho::is command bunx; then
    dyai::setup_skills
  else
    dybatpho::warn "bunx is not installed, skip skills"
  fi
}
