// opencode has no config-file hooks, so the dyai-guard pre-shell hook every
// other agent gets from dyai (global.policy.guard) runs here: before a bash
// call, refuse a removal of $HOME, / or the repository. opencode can only
// refuse from a plugin, so the asks stay with its own permission rules.
export const DyaiGuard = async ({ $, directory }) => ({
  "tool.execute.before": async (input, output) => {
    if (input?.tool !== "bash" || typeof output?.args?.command !== "string") return;
    const hook = JSON.stringify({ tool_input: { command: output.args.command }, cwd: directory });
    // A guard that is missing or answers nonsense refuses the command: a
    // guard that fails open is switched off without anyone being told.
    const broken = (why) => new Error(`dyai-guard ${why}; refusing the command`);
    const script = "command -v dyai-guard > /dev/null 2>&1 || exit 127; dyai-guard opencode";
    let run;
    try {
      run = await $`bash -c ${script} < ${Buffer.from(hook)}`.cwd(directory).quiet().nothrow();
    } catch (error) {
      throw broken(`could not run (${error?.message ?? error})`);
    }
    if (run.exitCode === 127) throw broken("is not on PATH");
    const verdict = run.stdout.toString().trim();
    if (!verdict) return;
    let parsed;
    try {
      parsed = JSON.parse(verdict);
    } catch {
      throw broken("gave an answer that is not JSON");
    }
    if (parsed?.decision === "deny") throw new Error(parsed.reason || "dyai-guard refused this command");
  },
});
