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
  assert_output '[["a",[["ls",[]],["use",["preset"]],["rm",["preset"]]]]]'
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
