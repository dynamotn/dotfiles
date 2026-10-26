# dyai hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `dyai` honest about what it installed and what each agent
actually enforces. External installs time out and are checked after they run.
Local edits are never overwritten silently. Drift between the config and the
machine is reported at session start. Subagent use becomes visible.

**Architecture:** Small additions to `scripts/lib/dyai.sh`, plus two new
commands in `home/dot_local/bin/executable_dyai.tmpl` (`status`,
`enforcement`), one Claude hook script, and one rule line in an `ai/`
partial. Every idea comes from the Intent Loop 2.2.1 docs, read 2026-10-26:
- verify by path, not by exit code;
- third-party initializers run with stdin closed and a time limit;
- report LOCAL EDITS instead of overwriting;
- report armed vs declared, silent when everything is armed;
- an enforcement map that classifies each rule as M (mechanical),
  S (skill-read) or D (declared);
- a routed subagent spawn is announced;
- security changes get an independent reviewer.

**Tech Stack:** bash on dybatpho, `jq`, `yq`, `timeout`, `sha256sum`, bats.

**Spec:** none written. The decisions come from the 2026-10-26 conversation.
Live self-test and `dyai eval` depend on the crew runner and live in
`2026-10-26-dyai-crew.md` (Tasks 7 and 8).

## Global Constraints

- No new dependency.
- Functions stay `dyai::<verb>` in `scripts/lib/dyai.sh`, in the existing
  doc-comment style. Tests go in `scripts/test/dyai.bats` with its `_stub`
  and `_write_config` helpers, unless a task names another file.
- Every changed script passes `dyshellint`.
- `dyai install` must still never abort on one failed item. It warns and
  moves on, as it does today.
- Hook scripts only observe: they print nothing, always exit 0, and never
  change a tool call. This is the `log-skill.sh` contract.
- A change to `home/.chezmoitemplates/ai/` keeps `claude_rules.bats` green.
  Check rendered templates with `chezmoi execute-template --source .`.
- Commit messages: Conventional Commits, scope `dyai` (or `claude` for the
  hook), and no agent attribution trailer.

## Review Focus

1. A skill CLI that exits 0 without installing anything is reported, not
   recorded as installed. Test in Task 1.
2. An installer that waits on stdin or hangs is killed after the timeout, and
   the install carries on. Test in Task 1.
3. A subagent file the user edited survives `dyai install`, even when
   upstream changed. Test in Task 2.
4. `dyai status --quiet` prints nothing on a fully armed machine and stays
   fast (under 2 s), because it runs at every Claude session start. Test in
   Task 4.
5. The generated enforcement table in `docs/dyai.md` cannot drift from the
   code. Test in Task 5.

---

### Task 1: Time-limited external installs, checked by path

**Files:**
- Modify: `scripts/lib/dyai.sh` (`setup_marketplaces`, `setup_plugins`,
  `setup_skills`, `setup_installers`)
- Test: `scripts/test/dyai.bats`

**Interfaces:**
- Produces: `dyai::run_external <cmd...>`. Runs the command with stdin
  closed under `timeout --kill-after=10 "${DYAI_EXTERNAL_TIMEOUT:-300}"`, and
  returns its exit code (124 on timeout).

Behaviour:
- Every external install call goes through `run_external`. Today these are
  `claude plugin marketplace add`, `claude plugin install`,
  `bunx … add` and `bash -c "${cmd}"`. All four already close stdin, so this
  adds only the time limit.
- `setup_skills`: after a successful `bunx`, the skill directory must exist
  (`dybatpho::is dir` follows symlinks, so a dangling link counts as
  missing). Otherwise warn
  `skill <name>: installer reported success but <target> is missing`.
- `setup_plugins`: after a successful install, re-read
  `installed_plugins.json`. If the plugin is still absent, warn the same way.
- On a verified skill install, record the skill's content hash (see Task 2's
  `dyai::dir_hash`) in `~/.cache/dyai/installed/skills/<name>.sha256`.

- [ ] **Step 1: Write the failing tests:**
  - `@test "a skill install that exits 0 but writes nothing is reported"`:
    the `bunx` stub exits 0. Assert the output names the missing target and
    no `.sha256` is recorded.
  - `@test "a hanging installer is cut off and install continues"`:
    `DYAI_EXTERNAL_TIMEOUT=1`, an installer command `sleep 5`, a second
    installer that succeeds. The first warns, the second's marker is written.
  - `@test "an installer reading stdin gets EOF"`: the command is `read x`.
    It finishes at once.
- [ ] **Step 2: Run** `bats scripts/test/dyai.bats`. Expected: the new tests FAIL.
- [ ] **Step 3: Implement** `run_external` and route the four call sites
  through it. Add the post-install checks.
- [ ] **Step 4: Run** the bats file and `dyshellint scripts/lib/dyai.sh`.
  Expected: PASS, and every existing `dyai.bats` test still passes.
- [ ] **Step 5: Commit** `fix(dyai): time-limit installers and check what they installed`.

### Task 2: Never overwrite a local edit

**Files:**
- Modify: `scripts/lib/dyai.sh` (`setup_subagents`, `subagent_codex`, plus
  new helpers)
- Test: `scripts/test/dyai.bats`

**Interfaces:**
- Produces:
  - `dyai::dir_hash <path>`. Prints one sha256 over every file under `path`,
    hashed with its relative path, in sorted order. Prints the plain file
    hash when `path` is a file.
  - `dyai::installed_hash <kind> <name> [hash]`. Prints the recorded hash.
    With a third argument, records it at
    `~/.cache/dyai/installed/<kind>/<name>.sha256`.
  - `dyai::locally_edited <kind> <name> <dest>`. Exit 0 when `dest` exists,
    a hash was recorded, and `dest` no longer matches it.

Behaviour: `setup_subagents` currently copies over `dest` whenever it differs
from the pinned file (`! cmp -s` then `cp`). That silently destroys a user's
edit. The new order:
1. Equal to the pinned file: nothing to do.
2. `locally_edited`: keep the file and warn
   `subagent <leaf>: LOCAL EDITS kept; delete <dest> to take the pinned copy`.
3. Otherwise copy it and record the hash.

The same rule applies to the Codex `.toml` (kind `codex-agents`).

- [ ] **Step 1: Write the failing tests:**
  - `@test "an edited subagent survives a changed upstream"`: install, append
    a line to `dest`, change the pinned file, install again. `dest` still
    holds the appended line and the output says `LOCAL EDITS`.
  - `@test "an untouched subagent follows upstream"`: same, without the edit.
    `dest` equals the new pinned file.
  - `@test "a subagent installed before hashes existed is replaced once"`:
    no recorded hash, `dest` differs. It is replaced and its hash recorded.
    Without a recorded hash nothing can tell an edit from an old copy, so
    this keeps today's behaviour.
  - `@test "dir_hash changes when a file is renamed"`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** the three helpers and the new copy order.
- [ ] **Step 4: Run** the bats file and `dyshellint`. Expected: PASS.
- [ ] **Step 5: Commit** `fix(dyai): keep locally edited subagents`.

### Task 3: Choose each subagent's model tier

**Files:**
- Modify: `schemas/dyai.schema.yaml` (add `models` to a subagent source)
- Modify: `home/private_dot_config/dyai/config.yaml.tmpl`
- Modify: `scripts/lib/dyai.sh` (`setup_subagents`, `subagent_codex`)
- Test: `scripts/test/dyai.bats`, `scripts/test/dyai_schema.bats`

**Interfaces:**
- Consumes: Task 2's copy order. The hash is taken over the rewritten
  content, so an override is not mistaken for a local edit.
- Produces: config key `global.subagents[].models`, a map from leaf name to
  `haiku | sonnet | opus | inherit`. The installer writes it into the Claude
  frontmatter as `model:` with `yq --front-matter=process`. The Codex
  conversion gets no model key: Codex names models by provider, and the
  user's Codex default applies.

Initial overrides in the config, following Intent Loop's tier table (reviews
and security never below the strongest tier):
`code-reviewer: opus`, `security-auditor: opus`, `architect-reviewer: opus`,
`research-analyst: sonnet`. Leave the other 30 at their upstream values
(21 sonnet, 10 inherit, 3 haiku today).

- [ ] **Step 1: Write the failing tests:**
  - `@test "a models override rewrites the frontmatter"`: the pinned file
    says `model: sonnet`, the override says `opus`. The installed file says
    `model: opus` and the body is unchanged.
  - `@test "an override is not reported as a local edit"`: install twice.
    There is no `LOCAL EDITS` warning.
  - In `dyai_schema.bats`: `@test "schema rejects an unknown subagent model"`
    with `models: {x: gpt}`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** the schema key, the config block and the rewrite.
- [ ] **Step 4: Run** `bats scripts/test/dyai.bats`, `./scripts/test.sh --dyai`
  and `dyshellint`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(dyai): pin subagent model tiers in the config`.

### Task 4: `dyai status`, armed vs declared

**Files:**
- Modify: `scripts/lib/dyai.sh`
- Modify: `home/dot_local/bin/executable_dyai.tmpl` (`_spec_status`, `_status`)
- Modify: `home/private_dot_claude/settings.json.tmpl` (SessionStart)
- Test: `scripts/test/dyai.bats`, `scripts/test/claude_settings.bats` and its
  fixture `scripts/test/fixtures/claude-settings.expected.json`

**Interfaces:**
- Consumes: Task 2's `locally_edited` and `installed_hash`.
- Produces: `dyai::status [quiet]`. Prints one line per drift as
  `<agent> <kind> <name>: <problem>`. Exits 1 on any drift. With `quiet`, a
  clean machine prints nothing. CLI form: `dyai status [--quiet|-q]`.

Checks, for installed agents only:

| kind | declared in | armed when |
|---|---|---|
| skill | `global.skills` | the dir exists under `~/.agents/skills`; problem `LOCAL EDITS` when the hash differs |
| plugin | `agents.claude.plugins` | the key is in `installed_plugins.json` |
| subagent | `global.subagents` minus `exclude` | the file is in `~/.claude/agents`; `LOCAL EDITS` as in Task 2 |
| mcp | `global.mcp` | Claude: `dyai::claude_mcp_current` is non-empty in every config dir; other agents: the server name is under the block key `dyai::setup_mcp_agents` writes for them |
| hook | `global.hooks` | gemini `AfterAgent` holds `dyai-notify`; copilot `hooks/dyai.json` exists; codex `hooks.Stop` is set |
| policy | `global.policy.permissions` | gemini `policies/dyai.toml`, codex `rules/dyai.rules` and the opencode `permission` block exist |

SessionStart hook entry, appended to the existing `startup|resume|clear|compact`
matcher's hooks:
`command -v dyai >/dev/null 2>&1 && dyai status --quiet; true`, with
`"timeout": 5`.

- [ ] **Step 1: Write the failing tests:**
  - `@test "status is silent on an armed machine"`: run `dyai::install` with
    stubs, then `dyai::status quiet`. Output is empty and exit is 0.
  - `@test "status names a missing skill"`: remove the skill dir. Exit 1 and
    a line `claude skill alpha: missing`.
  - `@test "status names a locally edited subagent"`.
  - `@test "status skips agents that are not installed"`: no `gemini` on
    `PATH`, so there are no gemini lines.
  - `@test "status quiet finishes under 2 seconds"`: time the call with
    `SECONDS`.
  - Update the Claude settings fixture and let `claude_settings.bats` fail,
    then pass.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** `status`, the CLI command and the hook entry.
- [ ] **Step 4: Run** `bats scripts/test/dyai.bats scripts/test/claude_settings.bats`,
  `dyshellint`, and `chezmoi execute-template --source . --file home/private_dot_claude/settings.json.tmpl | jq .`.
  Expected: PASS and valid JSON.
- [ ] **Step 5: Commit** `feat(dyai): report drift between config and agents at session start`.

### Task 5: Enforcement map

**Files:**
- Modify: `scripts/lib/dyai.sh` (data table plus `dyai::enforcement`)
- Modify: `home/dot_local/bin/executable_dyai.tmpl` (`enforcement` command)
- Modify: `docs/dyai.md` (generated block in "Permissions in other agents")
- Test: `scripts/test/dyai.bats`

**Interfaces:**
- Produces: `dyai::enforcement`. Prints a Markdown table, one row per agent
  (claude, codex, gemini, opencode, copilot, agy, hermes). The columns are
  `approval`, `shell rules`, `path rules`, `stop/input hooks`, `mcp`,
  `subagents`. Each cell is one of:
  - `M`: written into the agent's own config, which enforces it;
  - `S`: reaches the agent only as instructions (`AGENTS.md`), so it holds
    only while the agent cooperates;
  - `-`: not carried over.
  A legend line follows the table.

The table is a TSV heredoc `DYAI_ENFORCEMENT`, placed in `dyai.sh` right
above `setup_policy`. Fill each cell from what the matching `setup_*` /
`permissions_*` function actually writes, not from the docs. Known cells from
the code today:
- copilot: `shell rules -`, `path rules -`, `approval -`;
- agy: `path rules -`, `stop/input hooks -`;
- opencode: `stop/input hooks -` (its hunk plugin is not a stop hook);
- `subagents` is `M` for claude and codex only, `-` for the rest.

Every `-` and `S` row comes from the instruction text that dyai renders into
`AGENTS.md`, so it is `S` wherever the agent reads `AGENTS.md`.

`docs/dyai.md` gets
`<!-- dyai:enforcement:start -->…<!-- dyai:enforcement:end -->` holding the
command's output.

- [ ] **Step 1: Write the failing tests:**
  - `@test "enforcement marks copilot shell rules as not carried"`.
  - `@test "enforcement marks claude and codex subagents as mechanical"`.
  - `@test "docs enforcement block matches the command"`: extract the block
    between the markers and compare it with `dyai::enforcement` output. This
    is the drift check.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** the table and the command, then paste the output
  between the markers.
- [ ] **Step 4: Run** the bats file and `dyshellint`. Expected: PASS.
- [ ] **Step 5: Commit** `docs(dyai): generate what each agent actually enforces`.

### Task 6: Visible subagent spawns, independent security review

**Files:**
- Create: `home/private_dot_claude/hooks/executable_log-agent.sh`
- Modify: `home/private_dot_claude/settings.json.tmpl` (PreToolUse `Agent`)
- Modify: `home/.chezmoitemplates/ai/verification.md.tmpl`
- Test: `scripts/test/claude_hooks.bats`, `scripts/test/claude_settings.bats`
  plus its fixture, `scripts/test/claude_rules.bats`

**Interfaces:**
- Produces: `log-agent.sh`, written to the `log-skill.sh` contract. It
  appends
  `{ts, agent: .tool_input.subagent_type, model: .tool_input.model, description: .tool_input.description, cwd, session}`
  to `${XDG_STATE_HOME:-~/.local/state}/claude/agent-usage.jsonl`, prints
  nothing, and exits 0. An empty `subagent_type` is logged as
  `general-purpose`, the harness default.

PreToolUse entry: matcher `Agent`, command `bash ~/.claude/hooks/log-agent.sh`,
`"async": true`, next to the `Skill` entry.

Rule line appended to `verification.md.tmpl`, as a bullet:
"A change on a security path (credentials handling, permissions, hooks,
anything under `secrets/`) is reviewed by a fresh subagent that did not write
it. A security fix counts as proven only when reverting it makes its test
fail."

- [ ] **Step 1: Write the failing tests** in `claude_hooks.bats`:
  - `@test "log-agent records type and model"`: pipe
    `{"tool_input":{"subagent_type":"Explore","model":"haiku","description":"x"},"session_id":"s"}`
    and assert one JSONL line with `agent=="Explore"` and `model=="haiku"`,
    empty stdout, exit 0.
  - `@test "log-agent never fails on garbage input"`: pipe `not json`. Exit 0,
    no output, no file written.
  - Update the settings fixture.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** the hook, the settings entry and the rule line.
- [ ] **Step 4: Run** `bats scripts/test/claude_hooks.bats scripts/test/claude_settings.bats scripts/test/claude_rules.bats`,
  `dyshellint home/private_dot_claude/hooks/executable_log-agent.sh`, and
  render `verification.md.tmpl`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(claude): log every subagent spawn`.

## Out of scope (named, not built)

- Blocking a spawn that has no routing decision (Intent Loop's ledger hook).
  It overlaps `laya`; log first, decide later.
- Installing subagents for Gemini, opencode and Copilot, which today get none.
- A second subagent source (wshobson/agents). Add it as a selective `include`
  once Task 2 protects local edits.
- Content-hash updates with `--check` for skills. Today `dyai` never updates
  an installed skill; Task 2's hashes are the base for it.
