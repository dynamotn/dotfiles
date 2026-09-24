# Working in this repository

This is a [chezmoi](https://www.chezmoi.io) dotfiles repository. These notes
cover what is specific to it; the machine-wide agent rules live in
`~/.config/AGENTS.md` (generated from `home/.chezmoitemplates/ai/`) and still
apply here.

## Layout

| Path                      | What it holds                                        |
|---------------------------|------------------------------------------------------|
| `home/`                   | chezmoi source for `$HOME` (`.chezmoiroot` points here) |
| `home/.chezmoitemplates/` | shared template partials, included by name           |
| `home/.chezmoiscripts/`   | `run_once_` / `run_onchange_` hooks run on apply     |
| `root/`                   | source for system files applied to `/`               |
| `silos/`                  | symlinks and large submodules, for quick navigation  |
| `scripts/lib/`            | bash libraries                                       |
| `scripts/test/`           | bats tests, one file per library                     |
| `schemas/`                | YAML schemas for `dytoy` and for the secrets data    |
| `secrets/`                | age-encrypted secrets; `secrets/data/` is a submodule |
| `docs/`                   | notes on commands and key bindings                   |

## Chezmoi conventions

- Edit the source under `home/`, never the applied file in `$HOME`. The repo
  runs in `mode: symlink`, so a file in `$HOME` may be a symlink back into
  this tree — editing it there hides the change from review.
- File name prefixes carry meaning and are parsed by
  `scripts/lib/chezmoi_attrs.sh`: `dot_`, `private_`, `executable_`,
  `symlink_`, `encrypted_`, and the `.tmpl` suffix for Go templates.
- Check a template renders before committing:

  ```bash
  chezmoi execute-template --source . --file home/path/to/file.tmpl
  ```

- Never run `chezmoi apply` to "test" a change. Show `chezmoi diff` instead
  and let the user apply.
- Factor text shared between several files into `home/.chezmoitemplates/` and
  include it with `{{ template "dir/name.md.tmpl" . }}`, rather than copying
  it. The AI instruction files (`CLAUDE.md.tmpl`, `AGENTS.md.tmpl`) are all
  thin wrappers around the partials in `home/.chezmoitemplates/ai/`.

## Shell code

- Libraries are bash, sourced (not executed), and named `scripts/lib/<area>.sh`
  with functions namespaced `<area>::<verb>`.
- They build on the `dybatpho` submodule (`scripts/lib/dybatpho`): use its
  helpers (`dybatpho::die`, `dybatpho::is`, `dybatpho::opts::*`) instead of
  hand-rolling argument parsing or error handling.
- Document with the existing comment style: `# @file`, `# @brief`,
  `# @description`, `# @arg`, `# @stdout`.
- Every library has a matching `scripts/test/<area>.bats`. A new function that
  can be tested gets a test in the same commit.

## Checks before reporting work done

```bash
./scripts/test.sh --all        # whole bats suite
./scripts/test.sh --dytoy      # dytoy YAML against its schema
./scripts/test.sh --secrets    # secrets YAML against schemas/secrets/
pre-commit run --all-files     # incl. betterleaks and detect-private-key
```

Run at least the suite covering what changed, and say which ones ran.

## Repository-specific rules

- There is deliberately no `CHANGELOG.md` here. Do not create one; the history
  lives in commit messages.
- Do not commit inside a submodule (`home/private_dot_config/nvim`,
  `silos/tmux`, the browser profiles, `secrets/data`, …) unless asked. A
  submodule pointer bump is its own commit.
- `secrets/data/` holds live credentials and is off limits — see the
  credentials section of the machine-wide agent rules.
- `.worktrees/` at the repository root is where worktrees go, and is already
  covered by the global gitignore.
