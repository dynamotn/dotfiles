# Architecture

How the pieces of this repository fit together: what is rendered from where,
in which order a machine is set up, and where to make a change. The guides
for each piece go deeper: [setup](setup.md), [secrets](secrets.md),
[dytoy](dytoy.md), [dyai](../scripts/lib/dyai/docs/dyai.md),
[kernel](kernel.md).

## Layers

The repository is one git tree holding several chezmoi sources, each applied
to its own destination:

| Source       | Destination        | Applied by                       | Holds |
|--------------|--------------------|----------------------------------|-------|
| `home/`      | `$HOME`            | `chezmoi apply`                  | the dotfiles; `.chezmoiroot` points here |
| `root/`      | `/`                | `scz apply` (chezmoi as root)    | system files: portage, sysctl, systemd, PAM... |
| `cascadeur/` | the repository     | `setup.sh`, before anything else | `.gitmodules`, rendered per machine |
| `secrets/`   | read by templates  | `chezmoi-dycrypt`                | age-encrypted data; `secrets/data/` is a submodule |

Around them sit the code that is not applied anywhere:

| Path            | Role |
|-----------------|------|
| `scripts/`      | `setup.sh`, `test.sh`, `kernel.sh`, container and Lima image scripts |
| `scripts/lib/`  | bash libraries (`<area>.sh`, functions `<area>::<verb>`), the `dybatpho` and `dyai` submodules |
| `scripts/test/` | one bats file per library, plus fixtures |
| `schemas/`      | YAML schemas for dytoy, `machines.yaml` and the secrets data |
| `docker/`       | toolbox images built from the same setup |
| `silos/`        | symlinks to the configs opened most, and large submodules |

## Setting up a machine

`scripts/setup.sh` drives a first install, and every step after it is a plain
chezmoi apply, so running it again is safe:

1. **Prerequisites.** Installs `chezmoi` (at least `.chezmoiversion`), `age`
   and `yq` when missing.
2. **`chezmoi init`.** Renders `home/.chezmoi.yaml.tmpl` into
   `~/.config/chezmoi/chezmoi.yaml`. This is where the machine is described
   (see [Machine data](#machine-data)); `--identities` answers which secrets
   to decrypt.
3. **Submodules.** Applies `cascadeur/` to render `.gitmodules`, so a machine
   only clones the submodules it uses (tmux only with the tmux multiplexer,
   awesome only on X...).
4. **SSH, then the network.** Applies `~/.ssh`, then `~/.config/dynet` and the
   git config. `network::detect` (`scripts/lib/network.sh`) picks git mirrors
   and a proxy for the network the machine is on, so the clones that follow
   reach their remotes.
5. **Everything else.** A full `chezmoi apply`, which also runs the hooks in
   `home/.chezmoiscripts/`.
6. **System layer.** `scz apply` on Linux, and on macOS for `/Applications`
   and `/private`. Skipped inside a container unless `--system`, and without
   root.

## Machine data

Every template reads the same data, from three places:

- **Detected** by `home/.chezmoi.yaml.tmpl`: `osid` (`<os>-<distro>`),
  `inContainer`, `initSystem` (the init system that runs, not the one
  installed), the path of `bash`.
- **Asked once** at `chezmoi init` with `prompt*Once`: `code`, `place`,
  `kind`, `company`, the GUI server, window manager, browser, mail client,
  multiplexer and so on. The options and their defaults are in
  `home/.chezmoidata/choices.yaml`.
- **Known machines** in `home/.chezmoidata/machines.yaml`, keyed by `code`,
  pre-answer those questions. Only what is safe to publish lives there
  (`schemas/machines.schema.yaml` checks it); hostnames and proxies live
  encrypted under `secrets/data/`.

The rest of `home/.chezmoidata/` is static data shared by templates: the
catppuccin palette, mirrors, NTP servers, kernel and storage settings,
companies. `root/.chezmoidata/` links to the files the system layer needs, so
one value serves both layers (the NTP list feeds both `timesyncd.conf` and
`chrony.conf`).

A check shared by several files becomes a partial that prints `true` or
nothing, such as `machine/zram.tmpl` for "this machine runs zram", used by the
sysctl, zram-init, zram-generator and dytoy templates alike.

To branch on a machine, test this data in the template (`{{ if eq .kind
"laptop" }}`), or leave a whole path out in `home/.chezmoiignore.tmpl` or
`root/.chezmoiignore.tmpl`. Prefer the ignore file when a file makes no sense
on a machine at all.

## Templates

- **Symlink mode.** `mode: symlink` makes every plain file in `$HOME` a link
  back into this tree, so editing it in `$HOME` edits the source. Templates,
  private, executable and encrypted files are written as real files instead.
  Always edit the source under `home/`.
- **Names carry attributes.** `dot_`, `private_`, `executable_`, `symlink_`,
  `encrypted_`, `create_`, `run_*` and the `.tmpl` suffix;
  `scripts/lib/chezmoi_attrs.sh` parses them for the tooling.
- **Partials.** Text shared by several files lives in
  `home/.chezmoitemplates/<area>/` and is included with
  `{{ template "<area>/<name>" . }}`. `root/` is a source of its own, so its
  `.chezmoitemplates/` and `.chezmoidata/` hold symlinks to the partials and
  data of `home/` it needs; add a link there when a system file needs one.
- **Externals.** `home/.chezmoiexternals/*.yaml.tmpl` download archives and
  files (themes, fonts, dictionaries, the Mozilla add-ons...) at apply time.
- **Removals.** `home/.chezmoiremove` lists targets to delete from `$HOME`
  when a file is retired.

## Hooks

`home/.chezmoiscripts/` holds the scripts chezmoi runs around an apply. The
name says when and in which order:

| Prefix                | Runs |
|-----------------------|------|
| `run_once_before_01-` | before the first apply: the submodules |
| `run_onchange_after_01-` | network detection |
| `run_onchange_after_02-install-*` | tool installs through dytoy, one hook per method: `os`, `binary`, `shell`, `mise` |
| `run_*_after_03-`     | per-tool setup: fish, nvim, tmux, AI agents, SSH known hosts... |
| `run_*_after_04-`     | services and jobs: rclone, cron, dyai node, notes |
| `run_onchange_after_05-reload-*` | reload a running program after its config changed |
| `run_once_after_99-`  | last: point the repository remote at its final URL |

A `run_onchange_` script embeds a hash of what it depends on in a comment, so
it reruns exactly when that changes. Hook bodies are bash on dybatpho, like
every script here; shared bits live in `home/.chezmoitemplates/chezmoiscripts/`.

`root/` has its own hooks in `root/.chezmoiscripts/` and
`root/etc/.chezmoiscripts/` (SELinux, PAM, SSL, Wi-Fi, CA store), filtered by
`root/.chezmoiignore.tmpl`.

## Tools: dytoy

Which tool comes from where is data, not code. Each tool has a YAML partial in
`home/.chezmoitemplates/dytoy/`, naming per platform its method: `os` (the
package manager, Homebrew on macOS), `binary` (a release download), `mise` or
`shell` (an install script). One install hook runs per method, through
`chezmoiscripts/dytoy_install.sh.tmpl`, and it hashes only the definitions
that name its method, so editing one tool reruns only its own installer.
`scripts/lib/dytoy.sh` does the installing, the same way on every platform.
Shared template logic is in `dytoy_lib/`. See [dytoy](dytoy.md).

## Secrets

Secrets are age-encrypted, never committed in clear. `encrypted_*.age` files
sit next to the files they become; structured secret data lives in the
`secrets/data/` submodule, per identity, and templates read it through
`chezmoi-dycrypt`. Which identities a machine may decrypt is part of its
machine data. See [secrets](secrets.md).

## AI agents

Seven agents run on this machine: Claude Code, Codex, Gemini, opencode,
Copilot, Antigravity and Hermes. They share one set of instructions and one
policy, so a rule is written once.

- **Instructions.** Each topic is a partial in `home/.chezmoitemplates/ai/`.
  `ai/all.md.tmpl` stitches them in reading order, and every agent's
  instruction file is a thin wrapper around it: `~/.codex/AGENTS.md`,
  `~/.gemini/GEMINI.md`, `~/.config/opencode/AGENTS.md`,
  `~/.copilot/copilot-instructions.md`, `~/.hermes/SOUL.md` and the generic
  `~/.config/AGENTS.md`. Claude is the exception: the absolute rules go into
  `~/.claude/CLAUDE.md` and each other partial becomes one file of
  `~/.claude/rules/`. `scripts/test/claude_rules.bats` fails when a partial
  has no rule file.
- **Policy and extensions.** `home/.chezmoitemplates/ai/dyai-data.yaml.tmpl`
  is the policy (allowed, asked and denied commands, sandbox, approval mode)
  and `~/.config/dyai/config.yaml` lists the skills, subagents, MCP servers,
  plugins and hooks. `dyai` (the `scripts/lib/dyai` submodule) writes them
  into each agent's own format, and `run_onchange_after_03-setup-ai` reapplies
  them when they change. See [dyai](../scripts/lib/dyai/docs/dyai.md).
  The same data holds `model_tiers` (which model is fast, standard or
  strong), read by dyai and by Claude's `route-agent` hook, and Claude's
  `defaultMode` and `attribution` are derived from its `approval` and
  `attribution` keys.
- **Hooks.** The desktop notification every agent sends on stop or when it
  waits for input is one partial, `ai/notify-hook.sh.tmpl`, rendered into
  Claude's `settings.json` and dyai's `global.hooks` (which carries it to the
  other agents). A crew worker (`DYAI_CREW` set) stays quiet.
- **Agent-specific files.** What only one agent understands stays in its own
  directory: `private_dot_claude/` (settings and hooks), `private_dot_codex/`,
  `private_dot_gemini/` (Gemini and Antigravity), `private_dot_config/opencode/`,
  `private_dot_copilot/`, `private_dot_hermes/`. Skills shared by every agent
  are in `dot_agents/skills/`.
- **Crew.** `dyai crew` runs agents on tasks in their own worktrees. Its
  `fences` in the dyai config list the paths a worker may not change: the
  secrets, the hooks, and the agent policy and instructions of every agent.

To change how agents behave, edit the partial or the policy, never one
agent's rendered file; `~/.claude/rules/agent-parity.md` spells out the rule.

## Git

- **Submodules.** `cascadeur/dot_gitmodules.tmpl` decides which submodules a
  machine clones. Every URL is the public HTTPS one; the network decides
  through `insteadOf` rewrites (written by dynet) whether git actually uses
  GitHub or the GitLab mirror, over SSH or HTTPS.
- **Worktrees.** Worktrees go in `.worktrees/`. The global git hooks in
  `home/private_dot_config/git/scripts/` fill a new worktree's submodules
  from the main checkout (`worktree_submodules.sh`, skipping those marked
  `worktreeInit = false`) and remove a merged worktree
  (`worktree_cleanup.sh`).
- **Commits.** The global `commit-msg` hook checks the message
  (`commit_message.sh`) and strips agent credit trailers
  (`strip_agent_credit.sh`), and gitlint rejects them; both read the agent
  names from `home/.chezmoitemplates/git/agent-names.tmpl`.
  `.pre-commit-config.yaml` runs the repository checks, secret scanners
  included.

## Development

- **Shell code** is bash built on dybatpho (`scripts/lib/dybatpho`): its
  option parser, logging, error handling and helpers, never hand-rolled ones.
  Lint with `dyshellint`.
- **Tests.** `./scripts/test.sh --all` runs every bats file in
  `scripts/test/` in parallel and validates the dytoy, dyai and secrets YAML
  against `schemas/`. CI (`.github/workflows/ci.yml`, mirrored in
  `.gitlab-ci.yml`) runs shellcheck, shfmt and the same suite with a fixture
  chezmoi config.
- **Where a change goes:**

  | To change...                       | Edit |
  |------------------------------------|------|
  | a dotfile                          | its source under `home/` |
  | a system file                      | its source under `root/`, apply with `scz` |
  | which machines get a file          | `home/.chezmoiignore.tmpl` or `root/.chezmoiignore.tmpl` |
  | a question asked at init           | `home/.chezmoi.yaml.tmpl` and `choices.yaml` |
  | a known machine's answers          | `home/.chezmoidata/machines.yaml` |
  | a tool to install                  | `home/.chezmoitemplates/dytoy/<tool>.yaml.tmpl` |
  | an instruction for every AI agent  | a partial in `home/.chezmoitemplates/ai/` |
  | an agent permission                | `home/.chezmoitemplates/ai/dyai-data.yaml.tmpl` |
  | a submodule                        | `cascadeur/dot_gitmodules.tmpl` |
