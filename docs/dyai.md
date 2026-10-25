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

`dyai use`, `ls` and `rm` operate on the git repository you run them in
(`dyai use` errors outside one).

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
  single `.md` files) whose agents install into every agent's agents
  directory. `exclude` drops named leaves from the baseline; a preset can
  still pull one per project.
- `commands` — pinned repos of command `.md` files, same shape as
  `subagents`. Nothing installs them globally; presets name them.
- `mcp` — MCP servers, each written into every MCP-capable agent in that
  agent's own format. An `env` map holds variable **names** only, never a
  secret value. Claude skips a server that an enabled Claude plugin of the
  same name already bundles (see [How it installs](#how-it-installs)).
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
`agents.claude.plugins`.

### `registry` — opt-in presets

Grouped by tool boundary so a project pulls in only what it uses:

- `languages` — one per language the Neovim config supports (`go`, `python`,
  `rust`, `typescript`, `frontend`, `vue`, `angular`, `java`, …)
- `infra` — `terraform`, `terragrunt`, `kubernetes`, `docker`, `aws`, `cicd`,
  `database`, `ansible`
- `presets` — cross-language domains: `testing`, `security`, `datascience`,
  `docs`, `shell`, and the domain agents kept out of the baseline (`desktop`,
  `mobile`, `graphql`, `realtime`), and `lifeos` (the thinking skills of
  [LifeOS](https://github.com/danielmiessler/LifeOS) that run without its
  runtime)

`dyai ls` prints the full, current list.

Each preset is `{subagents?, skills?, mcp?, commands?}`. Subagent names resolve
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
- **Codex / Hermes** — MCP merged into their TOML / YAML config.

The `filesystem` MCP server is scoped per config context: personal and
community trees by default, the enterprise tree inside an enterprise config
directory.

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
