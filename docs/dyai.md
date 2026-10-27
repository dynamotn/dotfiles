# dyai

`dyai` manages AI-agent extensions — skills, subagents, MCP servers, plugins,
hooks and policy — across every agent these dotfiles support (Claude, Gemini,
Copilot, opencode, Codex, Antigravity, Hermes), the way `mise` manages tools.
One declarative config describes a shared baseline installed for every agent,
plus a registry of opt-in presets a project pulls in on demand.

<!-- toc -->

- [Usage](#usage)
- [Configuration](#configuration)
  - [`global` — the baseline](#global--the-baseline)
  - [`agents.<name>` — agent-specific](#agentsname--agent-specific)
  - [`registry` — opt-in presets](#registry--opt-in-presets)
- [Per-project selection](#per-project-selection)
  - [`.dyai.toml`](#dyaitoml)
  - [What materialization writes](#what-materialization-writes)
- [How it installs](#how-it-installs)
  - [Permissions in other agents](#permissions-in-other-agents)
- [Crew](#crew)
- [Adding to the registry](#adding-to-the-registry)
- [Keeping the baseline lean](#keeping-the-baseline-lean)

<!-- tocstop -->

## Usage

| Command | What it does |
|---------|--------------|
| `dyai install` | Apply the whole config to every installed agent (the baseline). Also runs from the chezmoi setup hook on apply. |
| `dyai use <name>` | Opt the current project into a registry preset: record it and materialize its extensions into the project. |
| `dyai ls` | Print the global baseline, the registry, and this project's selected presets. |
| `dyai rm <name>` | Drop a preset from this project and remove the files it added. |
| `dyai mcp` | Serve `ls`, `use` and `rm` as MCP tools on stdio, so an agent can pull in a preset itself. |
| `dyai status [--quiet]` | Report what drifted between the config and each installed agent: missing skills, plugins, MCP servers, hooks or policy files, and files you edited locally. Claude runs `dyai status --quiet` at every session start; it prints nothing when everything matches. |
| `dyai update [--check]` | Update the installed global skills whose upstream changed, by content hash. A skill you edited is kept and named; one with no recorded hash that differs from upstream is kept too. The old copy goes to `~/.cache/dyai/backup/skills/`. `--check` only reports. |
| `dyai enforcement` | Print what each agent actually enforces of the shared config (see [Permissions in other agents](#permissions-in-other-agents)). |
| `dyai run`, `tasks`, `review`, `fix`, `merge`, `drop`, `logs` | Run a task on a headless agent in its own worktree, review it with another provider, and merge it (see [Crew](#crew)). |

`dyai use`, `ls` and `rm` operate on the git repository you run them in
(`dyai use` errors outside one).

`dyai mcp` is registered in `global.mcp` as the `dyai` server, so every agent
gets it. Its tools run in the agent's working directory, the same as the
commands, with stdin closed. A failed command comes back as a tool error, not a
protocol error, and the server keeps running. A preset name that is not plain
`[A-Za-z0-9._-]` is refused. What a preset adds, MCP servers and plugins at
least, may only load on the agent's next session.

## Configuration

The single source is `~/.config/dyai/config.yaml` (chezmoi source:
`home/private_dot_config/dyai/config.yaml.tmpl`), validated against
`schemas/dyai.schema.yaml`. It has three top-level sections.

### `global` — the baseline

Installed for every agent, every project:

- `skills` — [skills.sh](https://skills.sh) entries, kept lean: only
  cross-cutting skills every project benefits from (API design, architecture,
  documentation, prompt engineering, …). Anything tied to a language, tool or
  domain lives in a preset instead.
- `subagents` — a pinned repo (VoltAgent) and the category directories (or
  single `.md` files) whose agents install into Claude's `~/.claude/agents`
  and, converted to TOML, Codex's `~/.codex/agents` (an agent granted no
  writing tool runs there in a `read-only` sandbox). Gemini
  (`~/.gemini/agents/*.md`), opencode (`~/.config/opencode/agents/*.md`,
  `mode: subagent`) and Copilot (`~/.copilot/agents/*.agent.md`) get a
  Markdown conversion in their own frontmatter; a read-only agent stays
  read-only there too (Gemini read tools only, opencode `edit`/`bash`
  denied, Copilot `read` and `search`). Every copy is hash-tracked, so a
  local edit is kept. `exclude` drops named
  leaves from the baseline; a preset can still pull one per project.
- `commands` — pinned repos of command `.md` files, same shape as
  `subagents`. Nothing installs them globally; presets name them.
- `mcp` — MCP servers, each written into every MCP-capable agent in that
  agent's own format. An `env` map holds variable **names** only, never a
  secret value. Claude skips a server that an enabled Claude plugin of the
  same name already bundles (see [How it installs](#how-it-installs)).
  `readonly: true` marks a server with no side effects or state between
  calls; Codex then gets `supports_parallel_tool_calls = true` for it.
- `hooks` — abstract events (`stop`, `input`) translated into each
  hook-capable agent's format.
- `installers` — a shell command per agent id, run once by `dyai install`
  (keyed by its hash under `~/.cache/dyai/installers/`) for a tool whose own
  installer does what the declarative arms cannot.
- `policy` — shared settings (permissions, theme, effort, approval mode).
  `permissions` carries the harness-enforced half of the machine-wide agent
  rules, in Claude's syntax: `deny` for credential stores and decrypting
  commands, `ask` for destructive ones. Claude reads it as is; the other
  agents get a translation (see [Permissions in other agents](#permissions-in-other-agents)).

### `agents.<name>` — agent-specific

Things only one agent understands, e.g. `agents.claude.marketplaces` and
`agents.claude.plugins`. `agents.claude.optional_plugins` are installed too
but switched off in `settings.json`: a plugin loads every skill it ships into
every session, so a domain plugin (the security research kits, redis, duckdb)
stays off until a project turns it on through a preset.

### `registry` — opt-in presets

Grouped by tool boundary so a project pulls in only what it uses:

- `languages` — one per language the Neovim config supports (`go`, `python`,
  `rust`, `typescript`, `frontend`, `vue`, `angular`, `java`, …)
- `infra` — `terraform`, `kubernetes`, `docker`, `aws`, `azure`, `gcp`,
  `gitops`, `pulumi`, `cicd`, `database`, `terragrunt`, `ansible`,
  `cloudflare`, `mongodb`, the data platform (`dbt`, `airflow`, `dagster`,
  `clickhouse`, `databricks`), and `temporal`
- `presets` — cross-language domains: `testing`, `security`, `compliance`,
  `research`, `datascience`, `docs`, `shell`, and the domain agents kept out
  of the baseline (`desktop`, `mobile`, `graphql`, `realtime`,
  `modernization`, `apidocs`), observability (`sentry`, `opentelemetry`,
  `sre`, `grafana`, `datadog`, `elastic`), `platform`, `finops`,
  `architecture`, product work (`product`, `office`, `jira`, `linear`,
  `notion`), `writing`, `marketing`, `stripe`, LLM work (`llm`, `langchain`,
  `huggingface`), `context` (context engineering for building agents),
  `lifeos` (the thinking
  skills of [LifeOS](https://github.com/danielmiessler/LifeOS) that run
  without its runtime), and `codegraph` (a code knowledge graph for large
  repos; run `codegraph init` in the project first), `openspec`
  (spec-driven changes; needs the `openspec` CLI and `openspec init`), and
  `onboarding`
  (getting to know an unfamiliar repo: Understand-Anything and archify)

`dyai ls` prints the full, current list.

Each preset is `{subagents?, skills?, mcp?, commands?, plugins?}`. Subagent names resolve
against the pinned `global.subagents` repo (materialize finds `<name>.md`
anywhere in the fetched tree), so a preset may reference any category — not
only the ones the baseline installs. Because the names are coupled to that
pinned ref, a bats test re-verifies them whenever the repo is cached.

## Per-project selection

`dyai use <name>` resolves `<name>` across `languages`/`infra`/`presets`
(ambiguous or unknown names error), records it, and materializes it. Re-running
converges; it never duplicates.

### `.dyai.toml`

A **personal**, git-ignored file at the repo root:

```toml
use = ["go", "security"]
materialized = [
  "/abs/path/.claude/agents/golang-pro.md",
  "/abs/path/.agents/skills/golang-code-style",
]
```

`use` is the presets you selected; `materialized` is the manifest of files
`dyai` wrote, used to prune on `dyai rm` or a registry change. `.dyai.toml` and
every materialized path are added to `.git/info/exclude` (the repo's personal
ignore), never the committed `.gitignore` — your preset choices never reach the
team, and are never committed.

### What materialization writes

- **subagents** → `./.claude/agents/<name>.md`, copied from the pinned repo
  (idempotent; unchanged files are left alone).
- **commands** → `./.claude/commands/<name>.md`, copied from the pinned
  `global.commands` repo the same way.
- **skills** → `./.agents/skills/` via `skills add` run in the project (no
  `-g`), so they are project-local, not global.
- **mcp** → Claude's project-**local** scope (`claude mcp add-json --scope
  local`, kept in `~/.claude.json`, not the shared `./.mcp.json`), tracked
  as `materialized_mcp` in `.dyai.toml`.
- **plugins** → `enabledPlugins` in `./.claude/settings.local.json` (Claude's
  personal project settings, also personal-ignored), tracked as
  `materialized_plugins`. Dropping the preset removes only the keys dyai set;
  the rest of that file, and plugins you toggled yourself, stay.

`dyai rm` (or re-running after editing the registry) prunes exactly the files a
dropped preset owned, and keeps a file another active preset still wants.
Pruning is confined to the `./.claude/agents/`, `./.claude/commands/` and
`./.agents/skills/` subtrees
and refuses any path with a traversal segment, so a crafted `.dyai.toml` cannot
turn it into an arbitrary delete. If a configured subagent source cannot be
fetched (e.g. offline), materialize refuses to prune rather than delete files
it could not recompute.

## How it installs

`dyai install` (and the setup hook) reads `global` and `agents.*` and brings
each installed agent in line, skipping any agent whose launcher is absent:

- **Claude** — marketplaces, plugins, skills, MCP (`claude mcp add-json`),
  hooks and policy, across the default and every enterprise config directory.
- **Gemini / Antigravity / Copilot / opencode** — MCP merged into each one's
  JSON config in its own shape; hooks where supported. Gemini's `stop` hook
  is `AfterAgent`, which fires once per turn.
- **Gemini baseline** — `~/.gemini/settings.json` also gets its `$schema`,
  `context.fileName` `["AGENTS.md", "GEMINI.md"]`, checkpointing (`/restore`),
  usage statistics and telemetry off, and `security.disableYoloMode`. These
  are fixed, not read from the config.
- **Codex / Hermes** — MCP merged into their TOML / YAML config. Codex also
  gets hooks, the baseline subagents as `~/.codex/agents/*.toml`, and the
  shell-scripts rules as the `shell-scripts` skill rather than inline in its
  `AGENTS.md`.

The `filesystem` MCP server is scoped per config context: personal and
community trees by default, the enterprise tree inside an enterprise config
directory.

The `dybrain` MCP server is the Obsidian vault's own script
(`~/Documents/DyBrain/99_System/99.03_Scripts/dev/vault-mcp.py`), launched
through `~/.local/bin/dybrain-mcp`: every session talks to one shared backend
on a Unix socket in `~/.local/state/dybrain/` (owner only), started by the
first session and left running, instead of each running its own copy with
`uv run --script`. It is declared only on the `pc`, `laptop` and `tablet` kinds
that install Obsidian. It never reads, lists or writes `ai: sensitive`
notes, and refuses writes to `ai: readonly` notes and templates. Its tools:

| Group   | Tools |
|---------|-------|
| Read    | `search`, `read`, `lookup`, `links`, `backlinks`, `list_notes`, `inbox`, `daily_tasks` |
| Health  | `check`, `wiki_kinds`, `wiki_health`, `frontmatter_summary` |
| Capture | `capture_fleeting`, `append_daily` |
| Create  | `create_permanent`, `create_literature`, `create_reference`, `create_note`, `create_person`, `create_asset` |
| Edit    | `append_note`, `set_properties`, `move`, `rename` |

The `create_*` tools render the vault's templates with `node`, and refuse a
note that would become `ai: sensitive` (a private decision, an ancestor, a
contact with personal data, a document or insurance asset). `move` and
`rename` go through the running Obsidian app so links are updated, and
refuse when Obsidian is closed, its CLI is off, or its window is hidden. The `second-brain`
agent rule tells every agent when to call these tools.

A `global.mcp` server named like an entry of `agents.claude.plugins`
(`context7` and `context7@claude-plugins-official`) is left to that plugin
in Claude, since the plugin bundles the same server and a second copy loads
every tool definition twice. If dyai registered it earlier, the registration
is removed, but only when it is still exactly dyai's definition; a server
you customized under that name stays. Other agents, which have no plugins,
still get it from `global.mcp`.

### Permissions in other agents

`dyai install` translates the `Bash(...)`, `Read(...)` and `Edit(...)` rules of
`global.policy.permissions` into each installed agent's own mechanism. The
`rtk git ...` spellings exist only for Claude's rtk hook and are dropped, and
a prefix in both lists is denied.

| Agent | Where | Shell `deny` / `ask` | Path rules |
|-------|-------|----------------------|------------|
| opencode | `permission` in `opencode.json` | `deny` / `ask` globs under `bash` | `read` / `edit` globs |
| Antigravity | `permissions` in `~/.gemini/antigravity-cli/settings.json` | `command(<prefix>)` in `deny` / `ask` | none (no documented glob form) |
| Gemini CLI | `~/.gemini/policies/dyai.toml`, owned by dyai | `commandPrefix`, `deny` / `ask_user` | none |
| Codex | `~/.codex/rules/dyai.rules`, owned by dyai | `prefix_rule`, `forbidden` / `prompt` | none |
| Hermes | `approvals.deny` in `~/.hermes/config.yaml` | deny globs only; no ask list | none |
| Copilot | — | no user-level config key | none |

Gemini, Codex and Antigravity match literal prefixes, not globs. A rule with a
`*` inside it (`git * main`) is not translated for them, and `dyai install`
warns. Codex and Antigravity also match whole words, so a rule without a word
boundary (`foo*`) would only cover `foo`; it is still translated, with a
warning. Write rules as `p:*` or `p *` to keep them exact everywhere.

The JSON and YAML targets are merged: your own rules stay, and a rule dropped
from the policy later is not removed. The two files dyai owns are rewritten
whole. The path rules reach only Claude and opencode, so for the other agents
the credential-store rules still rest on the instructions text alone.

`dyai enforcement` prints, for the whole shared config, what each agent
actually enforces. The table below is its output; a test fails when the two
drift apart.

<!-- dyai:enforcement:start -->
| agent | approval | shell rules | path rules | stop/input hooks | mcp | subagents |
|---|---|---|---|---|---|---|
| claude | M | M | M | M | M | M |
| codex | M | M | S | M | M | M |
| gemini | M | M | S | M | M | M |
| opencode | M | M | M | - | M | M |
| copilot | - | S | S | M | M | M |
| agy | - | M | - | - | M | - |
| hermes | - | M deny | - | - | M | - |

M: written into the agent's own config, which enforces it. M deny: deny rules only; ask rules are dropped.
S: instructions only (AGENTS.md and kin), held while the agent cooperates. -: not carried over.
A shell rule with an inner * is not written for gemini, codex or agy (literal prefixes only).
<!-- dyai:enforcement:end -->

## LSP

`dyai install` also shares Neovim's configured language servers with every
other agent (`dyai_lsp::setup`, run before marketplaces/plugins):

- **Export.** Headless Neovim is asked for its configured servers, minus
  `global.lsp.exclude` (noisy or non-code-intelligence ones: `harper_ls`,
  `typos_lsp`, `sonarlint`, `copilot`, `ast_grep`, `tailwindcss`), into a
  manifest at `${XDG_CACHE_HOME:-~/.cache}/dyai/lsp.json`.
- **Claude** gets its own `dyai-lsp` plugin (registered via a local
  marketplace), built from that manifest. The official `*-lsp` plugins it
  replaces (`pyright-lsp`, `lua-lsp`, `typescript-lsp`, `gopls-lsp`,
  `rust-analyzer-lsp`) are set to `false` in `enabledPlugins`, so a copy
  still installed from before never runs next to it; dyai does not
  uninstall them.
- **Copilot, opencode and Hermes** get the same servers merged into each
  one's own LSP config format. In opencode a server is keyed by opencode's
  own built-in id when that built-in is the same server (`rust_analyzer` is
  written as `rust`, `lua_ls` as `lua-ls`, ...), so it replaces the
  built-in; a built-in that is a different server for the same extensions
  (opencode's `typescript` next to Neovim's `vtsls`) gets
  `{"disabled": true}`. Built-ins for languages Neovim has no server for are
  left alone.
- **Codex, Gemini and agy** have no native LSP integration, so they get the
  servers bridged through a `serena` MCP server instead
  (`global.lsp.serena.ref` pins the commit; `global.lsp.serena.contexts`
  sets each agent's `--context`). Two languages (`gopls`, `lua_ls`) are
  PATH-only in serena, so dyai also writes small shims for them.
- A hand-written entry you already have in any of these configs is left
  alone — dyai tracks only the keys it wrote itself and never overwrites one
  it does not own, warning instead.

Every server command is wrapped by `dyai-lsp-exec`, a trust gate: inside a
directory Neovim holds untrusted (`.worktrees/dyreview-*`, released only by
`:DyReview trust` in that Neovim session), the language server is refused
rather than started. Everywhere else it `exec`s straight through. The
serena MCP server itself is launched through the same gate, since it reads
the project's `.serena/project.yml` and starts servers for every language
it finds.

**Limit of the gate.** It checks only the directory a server *starts* in,
i.e. the agent's working directory. An agent started outside a held
directory that then opens files inside one gets no protection: the server
is already running and is never asked again.

Any step here failing (no `nvim`, no `uvx`, `global.lsp.serena.ref` unset,
...) only warns; `dyai install` still finishes and installs plugins. With no
manifest (the export failed and none was left from an earlier run), the
Copilot, opencode and Hermes configs, serena's `ls_specific_settings` and
its shims are left as the last good run wrote them rather than emptied.

**Claude warns about `dyai-lsp@dyai-lsp` on a fresh machine.** The
`dyai-lsp` marketplace is a local directory dyai generates, so it is
registered at runtime by `dyai install` (`claude plugin marketplace add`),
not through `extraKnownMarketplaces` in `settings.json`. Until the first
`dyai install`, Claude sees `dyai-lsp@dyai-lsp` enabled but cannot find its
marketplace, and may warn about it; the warning goes away once
`dyai install` has run.

**Refreshing.** Re-run `dyai install` whenever Neovim gains or loses a
language server (e.g. after `:Mason` installs one) to update every agent.

**Fresh machine.** The apply-time hook runs before Neovim's own setup, so it
cannot see servers Neovim has not installed yet. Run `dyai install` once by
hand after Neovim's first start on a new machine, so every agent picks up
the servers it just installed.

## Crew

`dyai run` hands a task to an agent CLI running headless in its own git
worktree; `dyai review` has a different provider read the change; `dyai merge`
takes it into the current branch once the review passed. dyai never calls a
provider API and holds no model: each worker is the real CLI, so it keeps the
skills, MCP servers and policy `dyai install` gave it. The design is in
[`2026-10-26-dyai-crew.md`](superpowers/plans/2026-10-26-dyai-crew.md).

| Command | What it does |
|---------|--------------|
| `dyai run [--agent A\|auto] [--plan FILE] [--detach] PROMPT` | Create `.worktrees/crew-<id>` on branch `crew/<id>` from `HEAD`, run the agent there, commit what it left. `auto` walks `global.crew.fallback`. `PROMPT` may be `-` (stdin). Prints the task id. Ctrl-C stops the agent too and records the task `interrupted`. |
| `dyai tasks` | One line per task: `id`, status, agent, summary. A dead `running` task reads `lost`. |
| `dyai logs [--follow] [--err] ID` | The agent's stdout (or stderr). `--follow` follows a running agent and stops when it ends. Options always come before the id or the prompt: parsing stops at the first argument. |
| `dyai review [--by A] [--detach] ID` | A read-only review by another agent; records `pass`, `fail` or `unknown`. |
| `dyai fix [--detach] ID` | After a `fail`: the writer again, in the same worktree, with the review. Voids the verdict. |
| `dyai merge ID` | Merge a reviewed task into the current branch (see below). |
| `dyai drop ID... \| --finished` | Remove worktrees; delete branches only once merged (`git branch -d`). |
| `dyai eval [--agent A] [CASE...]` | Spends quota. Runs the cases in `scripts/test/evals/` (a seeded scratch repo, a task, a `check.sh`) and prints `PASS`, `FAIL` or `BLOCKED` per case. Run it after changing an `ai/` partial, a hook or the policy; add a case after each incident. |
| `dyai selftest [AGENT...]` | Spends quota. Asks each agent to run `dyai-selftest-probe allow` and `deny`, with an allow flag that admits both, so only the shared deny rule `Bash(dyai-selftest-probe deny *)` can stop the second. The result is checked against the [enforcement table](#permissions-in-other-agents): `PASS`, `FAIL`, or `BLOCKED` (the agent could not run, ran no command, or never tried the denied call: a missing `deny` marker counts only when the agent's output shows the attempt). |

A task id reads `<date>-<time>-<agent>-<4 hex>`. Task state is one
append-only `tasks.jsonl` in `<main checkout>/.dyai/crew/`, next to each
task's prompt, output, review and plan; `.dyai/`, `.worktrees/` and the result
file are added to the personal ignore. A run from inside a worktree still
creates its worktree under the main checkout.

**How a task ends.** The prompt asks the agent to write
`.dyai-result.json` (`{"status": "done|failed|partial", "summary": "..."}`)
and to stay on its branch. dyai then decides, in this order: a timeout
(`global.crew.timeout`, the whole process group is stopped); a rate limit or
an auth failure read from the agent's error output (`rate_limited`,
`blocked`: the agent cools down for `global.crew.cooldown` seconds and `auto`
moves to the next one); an agent that left `crew/<id>` (`failed`); the result
file. `done` also needs evidence: a task that claims done with no commit is
`failed`. An attempt that ended with nothing in it gives its worktree back at
once, since each registered worktree enlarges Claude Code's sandbox profile.

**Reviews.** The reviewer runs read-only (claude `plan`, codex `read-only`,
gemini `plan`, opencode `--agent plan`, copilot with shell and write denied)
and gets the task, the summary, the plan if there was one, and the diff
(inline up to 96 KB, else as `.dyai-review.diff` in the worktree). Its answer
must hold a line `{"verdict":"pass|fail","findings":[...]}`; dyai reads it
from each agent's own output envelope. Anything else is `unknown`, and
`unknown` never passes. `global.crew.reviewer` maps each writer to its
reviewer. Set `global.crew.model.copilot` to a non-Anthropic model when
copilot reviews claude: its default model is Claude.

**Merging.** `dyai merge` refuses unless the task is `done`, the current
branch is not `main` or `master` (make an integration branch first), the
working tree is clean, and, with `require_review` (the default), the verdict
is `pass` on the branch head that was reviewed. A diff that touches a
`global.crew.fences` pathspec (`.github/`, `.chezmoiscripts/`, `secrets/`,
`*.age`, `.env*`) stops at `needs_human`. Then `git merge --no-ff --no-commit`;
a conflict aborts (`conflict`), and `global.crew.gate` runs on the merged
tree (`gate_failed` aborts). A clean merge commits and drops the task.

**Views.** With `global.crew.panes: auto`, each started worker gets a zellij
pane following its log, and each review opens `hunk diff <base> crew/<id>`.
Inside zellij these float; outside it they land in a background session named
`dyai`, shown in a kitty tab when nothing is attached to it. Without zellij,
a kitty tab. `dyai-hunk` opens through the same path.

**From an agent.** `dyai mcp` serves the crew as tools too: `crew_run`
(always detached; returns the id), `crew_tasks`, `crew_review` and `crew_fix`
(detached), `crew_merge`, `crew_drop` and `crew_logs`. Every id, agent and plan
path is checked before anything runs; a prompt is passed as one string. A plan
must be inside the repository, and neither under a `global.crew.fences` path
nor in `.git/` (the CLI refuses those too): dyai reads it itself and sends it
to other providers.

**Lean workers.** `global.crew.profile: lean` (the default) keeps each worker
small. Claude gets `--setting-sources project,local` plus the permission
rules, sandbox and attribution of your `settings.json`, your `CLAUDE.md` and
`rules/*.md` as an appended system prompt, no MCP servers and no skills:
measured on a one-line answer, about 30k input tokens instead of 57k. With no
deny rule in `settings.json`, a worker falls back to the full profile rather
than run without them. opencode runs `--pure` (no external plugins), copilot
`--disable-builtin-mcps`; codex and gemini have no verified flag that keeps
their policy, so they always run full. `profile: full` keeps everything.

**Inside a worker** the env holds `DYAI_CREW=<id>`: the desktop hooks (notify,
sound, `dyai-hunk`, the SessionStart drift report) stay quiet.

What each agent can do headless, checked on 2026-10-26:

| | claude | codex | gemini | opencode | copilot |
|---|---|---|---|---|---|
| prompt | stdin | stdin (`-`) | stdin | attached file (`-f`) | stdin |
| shell in edit mode | what settings allow | yes, sandboxed | no | yes | yes |
| verified live here | yes | no (401) | no (not signed in) | no (no provider key) | yes |

Example:

```bash
git switch -c integrate
id=$(dyai run --agent claude "add a --dry-run flag to scripts/setup.sh" | tail -1)
dyai review "$id"        # copilot reviews a claude task by default
dyai fix "$id"           # only after a fail verdict; then review again
dyai merge "$id"
dyai drop --finished     # give back the worktrees of tasks that went nowhere
```

## Adding to the registry

Add a preset under the matching `registry` group in `config.yaml.tmpl`, listing
its `subagents` (leaf names present in the pinned repo) and `skills`
(`owner/repo@skill`, or a GitHub tree URL pinned to a commit and ending in the
skill's directory, for a skill nested where the skills CLI does not look).
Keep a skill out of `global` if it is specific to that
tool. Then `chezmoi apply` and `dyai use <name>` in a project.

## Keeping the baseline lean

Everything in `global` is loaded into every session of every agent, so it
costs context whether a project uses it or not:

- An MCP server spends context on its tool definitions as soon as it
  connects. Add one to `global.mcp` only when nearly every project needs
  it; otherwise give it to a preset (as `database` does for postgres and
  mysql).
- A skill's description is read in every session to decide when to fire.
  Write it as a trigger ("Use when …"), and keep a domain skill in a
  preset.
- Prefer a focused, preset-scoped subagent over another generalist one in
  the baseline.
