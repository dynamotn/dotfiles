// opencode has no config-file hooks, so the stop hook every other agent gets
// from dyai (global.hooks.stop) runs here: on session.idle, open the
// project's changes side by side in hunk.
const run = "command -v dyai-hunk > /dev/null 2>&1 && dyai-hunk; true";

export const DyaiHunk = async ({ $, directory }) => ({
  event: async ({ event }) => {
    if (event?.type !== "session.idle") return;
    try {
      await $`bash -c ${run}`.cwd(directory).quiet().nothrow();
    } catch {
      // A stop hook must never break the session.
    }
  },
});
