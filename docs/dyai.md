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
- [Adding to the registry](#adding-to-the-registry)

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
- `subagents` — a pinned repo (VoltAgent) and the category directories whose
  `*.md` agents install into every agent's agents directory.
- `mcp` — MCP servers, each written into every MCP-capable agent in that
  agent's own format. An `env` map holds variable **names** only, never a
  secret value.
- `hooks` — abstract events (`stop`, `input`) translated into each
  hook-capable agent's format.
- `policy` — shared settings (permissions, theme, effort, approval mode).

### `agents.<name>` — agent-specific

Things only one agent understands, e.g. `agents.claude.marketplaces` and
`agents.claude.plugins`.

### `registry` — opt-in presets

Grouped by tool boundary so a project pulls in only what it uses:

- `languages` — `go`, `python`, `rust`, `typescript`, `frontend`
- `infra` — `terraform`, `kubernetes`, `docker`, `aws`, `cicd`, `database`
- `presets` — cross-language domains: `testing`, `security`

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
- **skills** → `./.agents/skills/` via `skills add` run in the project (no
  `-g`), so they are project-local, not global.

`dyai rm` (or re-running after editing the registry) prunes exactly the files a
dropped preset owned, and keeps a file another active preset still wants.
Pruning is confined to the `./.claude/agents/` and `./.agents/skills/` subtrees
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
  JSON config in its own shape; hooks where supported.
- **Codex / Hermes** — MCP merged into their TOML / YAML config.

The `filesystem` MCP server is scoped per config context: personal and
community trees by default, the enterprise tree inside an enterprise config
directory.

## Adding to the registry

Add a preset under the matching `registry` group in `config.yaml.tmpl`, listing
its `subagents` (leaf names present in the pinned repo) and `skills`
(`owner/repo@skill`). Keep a skill out of `global` if it is specific to that
tool. Then `chezmoi apply` and `dyai use <name>` in a project.
