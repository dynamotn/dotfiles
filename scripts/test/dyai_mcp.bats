setup() {
  load test_helper
  setup_dotfiles_test_env
  # shellcheck disable=SC2154 # DOTFILES_DIR is set by test_helper.bash
  . "${DOTFILES_DIR}/scripts/lib/dyai_mcp.sh"
  # shellcheck disable=SC2154 # BATS_TEST_TMPDIR is set by bats itself
  CALLS="${BATS_TEST_TMPDIR}/calls"
  # Stand-ins for the dyai.sh commands the tools run.
  # dyshellint disable=SC2329 called by name through dyai_mcp::call
  function dyai::ls { printf 'presets: python\n'; }
  # dyshellint disable=SC2329 called by name through dyai_mcp::call
  function dyai::use {
    printf 'use %s\n' "$1" >> "${CALLS}"
    # A command that reads stdin must not eat the next request.
    cat > /dev/null
    printf 'Project uses preset %s\n' "$1"
  }
  # dyshellint disable=SC2329 called by name through dyai_mcp::call
  function dyai::rm { dybatpho::die "preset $1 is not used by this project"; }
  # Crew stand-ins: log their arguments, one per line.
  # dyshellint disable=SC2329 called by name through dyai_mcp::call
  function dyai_crew::run {
    printf 'run|%s\n' "$@" >> "${CALLS}"
    printf '20261026-120000-claude-abcd\n'
  }
  # dyshellint disable=SC2329 called by name through dyai_mcp::call
  function dyai_crew::list { printf '20261026-120000-claude-abcd\tdone\tclaude\tok\n'; }
  # dyshellint disable=SC2329 called by name through dyai_mcp::call
  function dyai_crew::review { printf 'review|%s\n' "$@" >> "${CALLS}"; }
  # dyshellint disable=SC2329 called by name through dyai_mcp::call
  function dyai_crew::fix { printf 'fix|%s\n' "$@" >> "${CALLS}"; }
  # dyshellint disable=SC2329 called by name through dyai_mcp::call
  function dyai_crew::merge { printf 'merge|%s\n' "$@" >> "${CALLS}"; }
  # dyshellint disable=SC2329 called by name through dyai_mcp::call
  function dyai_crew::drop { printf 'drop|%s\n' "$@" >> "${CALLS}"; }
  # dyshellint disable=SC2329 called by name through dyai_mcp::call
  function dyai_crew::state_dir { printf '%s\n' "${BATS_TEST_TMPDIR}/state"; }
  mkdir -p "${BATS_TEST_TMPDIR}/state"
  seq 1 600 > "${BATS_TEST_TMPDIR}/state/20261026-120000-claude-abcd.out"
}

# Send the given lines to the server, then reduce every reply with a jq filter
# @arg $1 string jq filter applied to the array of replies
# @arg $@ string Request lines
function exchange {
  local filter="$1" replies
  shift
  replies="$(printf '%s\n' "$@" | dyai_mcp::serve)"
  jq -sc "${filter}" <<< "${replies}"
}

# Build a tools/call request line
# @arg $1 string Request id
# @arg $2 string Tool name
# @arg $3 string Arguments, as JSON
function call_line {
  jq -cn --argjson id "$1" --arg name "$2" --argjson args "$3" \
    '{jsonrpc: "2.0", id: $id, method: "tools/call", params: {name: $name, arguments: $args}}'
}

@test "dyai mcp answers initialize with the client's protocol and a tools capability" {
  run exchange 'map([.id, .result.protocolVersion, (.result.capabilities | has("tools")), .result.serverInfo.name])' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}'
  assert_success
  assert_output '[[1,"2025-03-26",true,"dyai"]]'
}

@test "dyai mcp lists ls, use and rm, with preset required by use and rm" {
  run exchange 'map([.id, (.result.tools | map([.name, (.inputSchema.required // [])]))])' \
    '{"jsonrpc":"2.0","id":"a","method":"tools/list"}'
  assert_success
  assert_output --partial '[["a",[["ls",[]],["use",["preset"]],["rm",["preset"]],'
}

@test "dyai mcp lists the crew tools with their required arguments" {
  local filter='map(.result.tools | map(select(.name | startswith("crew_")))'
  filter+=' | map([.name, (.inputSchema.required // [])]))'
  run exchange "${filter}" '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
  local want='[[["crew_run",["prompt"]],["crew_tasks",[]],["crew_review",["id"]],["crew_fix",["id"]],'
  want+='["crew_merge",["id"]],["crew_drop",["id"]],["crew_logs",["id"]]]]'
  assert_output "${want}"
}

@test "crew_run starts a detached task and returns its id" {
  local line
  line="$(call_line 1 crew_run '{"prompt":"add a line","agent":"claude"}')"
  run exchange 'map(.result.content[0].text)' "${line}"
  assert_output '["20261026-120000-claude-abcd"]'
  run cat "${CALLS}"
  assert_output $'run|claude\nrun|add a line\nrun|\nrun|detach'
}

@test "crew_run keeps a hostile prompt as data" {
  local args line
  args="$(jq -cn --arg p "\$(touch ${BATS_TEST_TMPDIR}/pwned)" '{prompt: $p}')"
  line="$(call_line 1 crew_run "${args}")"
  run exchange 'map(.result.isError)' "${line}"
  assert_output '[false]'
  [[ ! -e "${BATS_TEST_TMPDIR}/pwned" ]]
  run grep -c 'touch' "${CALLS}"
  assert_output 1
}

@test "crew tools refuse a bad agent, id or plan" {
  local -a lines=()
  local id=20261026-120000-claude-abcd n=0 args
  for args in '{"prompt":"x","agent":"gpt"}' '{"id":"../x"}' "{\"id\":\"${id}\",\"by\":\"me\"}" \
    '{"prompt":"x","plan":"/etc/passwd"}' '{}'; do
    n=$((n + 1))
    lines+=("$(call_line "${n}" crew_run "${args}")")
  done
  lines[1]="$(call_line 2 crew_logs '{"id":"../x"}')"
  lines[2]="$(call_line 3 crew_review "{\"id\":\"${id}\",\"by\":\"me\"}")"
  lines[4]="$(call_line 5 crew_merge '{}')"
  run exchange 'map([.id, .result.isError])' "${lines[@]}"
  assert_output '[[1,true],[2,true],[3,true],[4,true],[5,true]]'
  [[ ! -e "${CALLS}" ]]
}

@test "crew_review and crew_fix run detached; merge and drop run in place" {
  local id=20261026-120000-claude-abcd
  local -a lines=()
  lines+=("$(call_line 1 crew_review "{\"id\":\"${id}\",\"by\":\"copilot\"}")")
  lines+=("$(call_line 2 crew_fix "{\"id\":\"${id}\"}")")
  lines+=("$(call_line 3 crew_merge "{\"id\":\"${id}\"}")")
  lines+=("$(call_line 4 crew_drop "{\"id\":\"${id}\"}")")
  exchange '.' "${lines[@]}" > /dev/null
  run cat "${CALLS}"
  local want="review|${id}"$'\n'"review|copilot"$'\n'"review|detach"$'\n'"fix|${id}"$'\n'"fix|detach"
  want+=$'\n'"merge|${id}"$'\n'"drop|${id}"
  assert_output "${want}"
}

@test "crew_tasks lists the tasks and crew_logs tails the output" {
  local id=20261026-120000-claude-abcd
  local -a lines=()
  lines+=("$(call_line 1 crew_tasks '{}')")
  lines+=("$(call_line 2 crew_logs "{\"id\":\"${id}\",\"lines\":3}")")
  lines+=("$(call_line 3 crew_logs "{\"id\":\"${id}\",\"lines\":9999}")")
  run exchange 'map(.result.content[0].text)' "${lines[@]}"
  run jq -r '.[0], .[1], (.[2] | split("\n") | length)' <<< "${output}"
  assert_line --index 0 $'20261026-120000-claude-abcd\tdone\tclaude\tok'
  assert_line --index 1 "598"
  assert_line --index 3 "600"
  assert_line --index 4 "500"
}

@test "dyai mcp skips notifications and blank lines, and reports a parse error" {
  run exchange 'map([.id, (.error.code // .result)])' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' '' 'not json' \
    '{"jsonrpc":"2.0","id":2,"method":"ping"}'
  assert_success
  assert_output '[[null,-32700],[2,{}]]'
}

@test "dyai mcp use runs dyai::use, returns its output, and keeps serving" {
  local use
  use="$(call_line 3 use '{"preset":"python"}')"
  run exchange 'map([.id, .result.isError, (.result.content[0].text // "")])' \
    "${use}" '{"jsonrpc":"2.0","id":4,"method":"ping"}'
  assert_success
  assert_output - << 'EOF'
[[3,false,"Project uses preset python\nNew MCP servers and plugins load on the next agent session."],[4,null,""]]
EOF
  assert_file_contains "${CALLS}" '^use python$'
}

@test "dyai mcp turns a failing command into isError and keeps serving" {
  local rm
  rm="$(call_line 5 rm '{"preset":"go"}')"
  run exchange 'map([.id, .result.isError, (.result.content[0].text // "" | contains("go is not used"))])' \
    "${rm}" '{"jsonrpc":"2.0","id":6,"method":"ping"}'
  assert_success
  assert_output '[[5,true,true],[6,null,false]]'
}

@test "dyai mcp refuses a missing or unsafe preset name without running the command" {
  local unsafe missing unknown
  unsafe="$(call_line 7 use '{"preset":"x\") or true"}')"
  missing="$(call_line 8 use '{}')"
  unknown="$(call_line 9 install '{}')"
  run exchange 'map([.result.isError, .result.content[0].text])' "${unsafe}" "${missing}" "${unknown}"
  assert_success
  assert_output - << 'EOF'
[[true,"invalid preset name: x\") or true"],[true,"invalid preset name: <missing>"],[true,"unknown tool: install"]]
EOF
  assert_file_not_exists "${CALLS}"
}

@test "dyai mcp answers an unknown method with method not found" {
  run exchange 'map([.id, .error.code])' '{"jsonrpc":"2.0","id":10,"method":"resources/list"}'
  assert_success
  assert_output '[[10,-32601]]'
}
