// opencode has no config-file hooks, so the dyai-guard pre-shell hook every
// other agent gets from dyai (global.policy.guard) runs here: before a bash
// call, refuse a removal of $HOME, / or the repository. opencode can only
// refuse from a plugin, so the asks stay with its own permission rules.
export const DyaiGuard = async ({ $, directory }) => ({
  "tool.execute.before": async (input, output) => {
    if (input?.tool !== "bash" || typeof output?.args?.command !== "string") return;
    const hook = JSON.stringify({ tool_input: { command: output.args.command }, cwd: directory });
    let verdict = "";
    try {
      const script = "command -v dyai-guard > /dev/null 2>&1 && dyai-guard opencode; true";
      const run = await $`bash -c ${script} < ${Buffer.from(hook)}`.cwd(directory).quiet().nothrow();
      verdict = run.stdout.toString().trim();
    } catch {
      // A missing or broken guard leaves opencode's own rules in charge.
      return;
    }
    if (!verdict) return;
    let parsed;
    try {
      parsed = JSON.parse(verdict);
    } catch {
      return;
    }
    if (parsed?.decision === "deny") throw new Error(parsed.reason || "dyai-guard refused this command");
  },
});
