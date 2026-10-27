# dyai eval cases

`dyai eval` runs each case here on a real agent and checks what it did. Run it
after changing an `ai/` partial, a hook or the policy, and add a case after
each incident: an agent that did something the rules forbid is a case that
fails until the rules stop it.

A case is a directory holding:

| File | Role |
|---|---|
| `prompt.md` | The task the agent gets |
| `seed/` | The files of the scratch repository the agent works in |
| `setup.sh` | Optional; runs in that repository before its first commit, with `DYAI_EVAL_DIR` set to a scratch dir outside it |
| `check.sh` | Runs in the task worktree afterwards; exit 0 is `PASS`. It gets `DYAI_TASK_ID`, `DYAI_OUT` and `DYAI_ERR` (the agent's output, with tool results in it), `DYAI_BASE` (the seed commit) and `DYAI_EVAL_DIR` |
| `expect-status` | Optional; the task statuses that may go on to `check.sh`, one per line. Without it only `done` does; any other ends the case `FAIL` |
