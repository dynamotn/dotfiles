---
name: chezmoi-source
description: Use when adding, renaming, or editing a dotfile on this machine - maps a $HOME path to its chezmoi source file under ~/Dotfiles/home, explains the dot_/private_/executable_/symlink_/encrypted_/.tmpl naming, and the diff-before-apply rule.
---

# Editing dotfiles through chezmoi

`$HOME` on this machine is rendered by chezmoi from `~/Dotfiles/home`
(`.chezmoiroot` points there) in `mode: symlink`. Many files under `$HOME`
are symlinks back into that tree, so an edit "in place" silently changes the
repo without review. Always edit the source.

## Find the source file

```bash
chezmoi managed | rg '<fragment>'        # is it managed at all?
chezmoi source-path ~/.config/foo/bar    # exact source file to edit
```

Not managed yet: `chezmoi add ~/.config/foo/bar`, then edit the file it
created. Never write a new file into `$HOME` and expect chezmoi to notice.

## Source name grammar

Attribute prefixes come in a fixed order, then `dot_` for a leading dot. The
same rule applies to every directory component.

| Prefix / suffix | Effect |
|-----------------|--------|
| `create_` | write once, never overwrite |
| `encrypted_` | stored age-encrypted in the repo |
| `private_` | mode 0600 / 0700 |
| `readonly_` | strip write bit |
| `empty_` | keep even if empty |
| `executable_` | set the executable bit |
| `symlink_` | file content is the link target |
| `dot_` | leading dot in the target name |
| `.tmpl` | Go template rendered at apply time |

Examples:

| Target | Source |
|--------|--------|
| `~/.config/fish/config.fish` | `home/private_dot_config/fish/config.fish` |
| `~/.claude/settings.json` | `home/private_dot_claude/settings.json` |
| `~/.local/bin/dyfox` | `home/dot_local/bin/executable_dyfox.tmpl` |
| `~/.config/tstruct/auth.json` | `home/private_dot_config/tstruct/encrypted_auth.json.age` |
| `~/.ssh/keys/enterprise-F1_ed25519` | `home/private_dot_ssh/keys/encrypted_private_readonly_enterprise-F1_ed25519.age` |

Every dotted directory in this repo gets `private_` as well; keep that
convention. `scripts/lib/chezmoi_attrs.sh` implements the rule in code for
encrypted files that `chezmoi add` cannot handle.

Scripts in `home/.chezmoiscripts/` run on apply: `run_once_` runs a single
time per machine, `run_onchange_` reruns when its rendered content changes.

## Templates

Shared text lives in `home/.chezmoitemplates/` and is included with
`{{ template "dir/name.md.tmpl" . }}`. The AI instruction files
(`CLAUDE.md.tmpl`, `AGENTS.md.tmpl`) are thin wrappers around
`home/.chezmoitemplates/ai/`; change the partial, not the wrapper.

Check a template renders before committing:

```bash
chezmoi execute-template --source ~/Dotfiles --file home/path/to/file.tmpl
```

## Preview, never apply

```bash
chezmoi diff            # show what apply would change
```

Show the diff and stop. `chezmoi apply`, `chezmoi destroy`, and
`chezmoi forget` write over the real `$HOME` and need the user's yes.

## Off limits

`secrets/data/`, `*.age`, and anything under `~/.ssh`, `~/.gnupg`, `~/.aws`
hold live credentials. Edit the shape (key names, templates, schemas), never
the value, and never run a decrypting command.
