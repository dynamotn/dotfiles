# dyshellint disable=SC2154 DOTFILES_DIR and BATS_TEST_TMPDIR come from bats and test_helper
setup() {
  load test_helper
  setup_dotfiles_test_env
  command -v bun &> /dev/null || skip "bun not found"
  BUN="$(command -v bun)"
  GUARD_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${GUARD_BIN}"
  cat > "${BATS_TEST_TMPDIR}/run.mjs" << SCRIPT
import { \$ } from "bun";
import { DyaiGuard } from "${DOTFILES_DIR}/home/private_dot_config/opencode/plugins/dyai-guard.js";
const hooks = await DyaiGuard({ \$, directory: process.cwd() });
try {
  await hooks["tool.execute.before"]({ tool: "bash" }, { args: { command: "rm -rf /" } });
  console.log("allowed");
} catch (error) {
  console.log("refused: " + error.message);
}
SCRIPT
}

# Run the plugin with only the stub guard, bash and its tools on PATH.
function _guard {
  PATH="${GUARD_BIN}:/usr/bin:/bin" run "${BUN}" "${BATS_TEST_TMPDIR}/run.mjs"
}

function _stub_guard {
  printf '#!/bin/sh\n%s\n' "$1" > "${GUARD_BIN}/dyai-guard"
  chmod +x "${GUARD_BIN}/dyai-guard"
}

@test "the opencode guard refuses a command when dyai-guard is missing" {
  _guard
  assert_output --partial 'refused: dyai-guard is not on PATH'
}

@test "the opencode guard refuses a command when dyai-guard answers nonsense" {
  _stub_guard 'echo not-json'
  _guard
  assert_output --partial 'refused: dyai-guard gave an answer that is not JSON'
}

@test "the opencode guard follows the verdict of dyai-guard" {
  _stub_guard 'true'
  _guard
  assert_output 'allowed'
  _stub_guard "echo '{\"decision\":\"deny\",\"reason\":\"no\"}'"
  _guard
  assert_output 'refused: no'
}
