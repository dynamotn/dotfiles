# Fish

Everything below is defined in `home/private_dot_config/fish/`: the `conf.d/`
snippets hold the abbreviations and aliases, `config.fish.tmpl` the editor
ones.

## Abbreviations

Expanded on Space/Enter, so the command line shows the full command before it
runs and the history keeps what really ran. A destructive one (`grh`, `gbd`,
`gcl`, `dsp`, `kdel`) is seen in full before Enter. Completion works on the
expansion, so none of them needs a completion of its own.

| Abbr | Expansion |
|------|-----------|
| `v` | `vim` (aliased to `nvim` when Neovim is available) |

### Docker

| Abbr | Expansion |
|------|-----------|
| `d` | `docker` |
| `db` | `docker build` |
| `di` | `docker image` |
| `dl` | `docker logs -f --tail 50` |
| `dph` | `docker push` |
| `dpl` | `docker pull` |
| `dps` | `docker ps` |
| `dr` | `docker run` |
| `drm` | `docker rm` |
| `drmi` | `docker rmi` |
| `drs` | `docker restart` |
| `dsp` | `docker system prune` |
| `dw` | `docker inspect` |
| `dx` | `docker exec -it` |

### Docker Compose

`docker-compose` is the standalone Compose v2 binary dytoy installs.

| Abbr | Expansion |
|------|-----------|
| `c` | `docker-compose` |
| `cb` | `docker-compose build` |
| `cl` | `docker-compose logs -f --tail 50` |
| `cpl` | `docker-compose pull` |
| `crs` | `docker-compose restart` |
| `cu` | `docker-compose up` |
| `cx` | `docker-compose exec` |

### Git

| Abbr | Expansion |
|------|-----------|
| `g` | `git` |
| `ga` | `git add` |
| `gai` | `git add -i` |
| `gap` | `git add -p` |
| `gb` | `git branch` |
| `gbd` | `git branch -D` |
| `gbl` | `git blame` |
| `gc` | `git commit -v` |
| `gca` | `git commit -v --amend` |
| `gcan` | `git commit -v --amend --no-edit --reset-author` |
| `gcm` | `git commit -m ""`, the cursor between the quotes |
| `gcl` | `git clean -df` |
| `gco` | `git checkout` |
| `gcp` | `git cherry-pick` |
| `gcpa` | `git cherry-pick --abort` |
| `gcpc` | `git cherry-pick --continue` |
| `gd` | `git diff` |
| `gdc` | `git diff --cached` |
| `gf` | `git fetch` |
| `gfa` | `git fetch --all -p` |
| `gfu` | `git fetch --unshallow` |
| `gg` | `git log --graph` with a custom one-line format |
| `ggp` | `git log -p` |
| `ggs` | `gg` with `--stat` |
| `gl` | `git pull` |
| `gm` | `git merge --ff` |
| `gmc` | `git merge --continue` |
| `gmt` | `git mergetool` |
| `gmv` | `git mv` |
| `gn` | `git clone --recursive --depth 1` |
| `gnb` | `git checkout -b` |
| `gp` | `git push` |
| `gph` | `git push gh` |
| `gpo` | `git push -u origin` |
| `gpt` | `git push --tags` |
| `grb` | `git rebase` |
| `grba` | `git rebase --abort` |
| `grbc` | `git rebase --continue` |
| `grbi` | `git rebase -i` |
| `grh` | `git reset --hard` |
| `grH` | `git reset HEAD` |
| `grm` | `git remote` |
| `grma` | `git remote add` |
| `grmd` | `git remote remove` |
| `grmu` | `git remote set-url` |
| `grs` | `git reset --soft` |
| `grv` | `git revert` |
| `gs` | `git status` |
| `gsh` | `git show` |
| `gsm` | `git submodule` |
| `gsn` | `git snapshot` |
| `gst` | `git stash` |
| `gstd` | `git stash drop` |
| `gstp` | `git stash pop` |
| `gsts` | `git stash show --text` |
| `gsu` | `git submodule update --init --recursive --remote` |
| `gt` | `git tag` |
| `gwt` | `git worktree` |

Completion for `git` extends the one fish ships with, in
`completions/git.fish`: commands that only accept tracked files (`rm`, `blame`,
`ls-files`, `log`, …) no longer offer untracked ones, `clean` offers exactly
what it would delete, `mergetool` the conflicted files, `add`, `diff`,
`commit`, `reset` and `restore --staged` (and so `ga`, `gd`, `gdc`, `gc`, `grH`)
also the submodules moved to another commit, staged or not as each command
expects, and every alias of
`~/.config/git/config` gets the argument it really takes — a stash for
`stash-rename`, a remote for `unshallow` and `mirror`, nothing at all for
`root`, `up` or `snapshot`.

### Kubectl

| Abbr | Expansion |
|------|-----------|
| `k` | `kubectl` |
| `ka` | `kubectl apply -f` |
| `kc` | `kubectl create` |
| `kccc` | `kubectl config current-context` |
| `kcdc` | `kubectl config delete-context` |
| `kcsc` | `kubectl config set-context` |
| `kcuc` | `kubectl config use-context` |
| `kd` | `kubectl describe` |
| `kdel` | `kubectl delete` |
| `ke` | `kubectl edit` |
| `kg` | `kubectl get` |
| `kgj` | `kubectl get -o json` |
| `kgy` | `kubectl get -o yaml` |
| `kk` | `kubectl apply -k` |
| `kl` | `kubectl logs` |
| `klf` | `kubectl logs -f --tail 50` |
| `kr` | `kubectl rollout` |
| `ksc` | `kubectl scale` |
| `kx` | `kubectl exec -it` |

Completion for `kubectl` comes from `kubectl completion fish`;
`completions/kubectl.fish` keeps that and adds what it misses, so
`kubectl config current-context` and friends no longer fall back to file names,
`set-cluster`/`set-credentials` name what is in the kubeconfig and `-k` offers
the directory of a kustomization, which `kk` gets through its expansion. The
wrappers `grc` installs used to pass their arguments through `eval`, which lost
empty and quoted ones and broke completion for every command they colour
(`kubectl`, `docker`, `systemctl`, …).

### Helm

| Abbr | Expansion |
|------|-----------|
| `h` | `helm` |
| `hd` | `helm-docs` |
| `hdel` | `helm delete` |
| `hdu` | `helm dependency update` |
| `hgv` | `helm get values` |
| `hl` | `helm ls` |
| `hs` | `helm secrets` |
| `hu` | `helm upgrade --install` |

Completion for `helm` comes from `helm completion fish`;
`completions/helm.fish` keeps that and stops the file names it falls back to
when the cluster is out of reach and a release name cannot be listed, and makes
`helm dependency` offer chart directories.

### Google Cloud

| Abbr | Expansion |
|------|-----------|
| `G` | `gcloud` |
| `Gal` | `gcloud auth login` |
| `Gb` | `bq query --use_legacy_sql=false` |
| `Gc` | `gcloud compute` |
| `Gca` | `gcloud compute addresses` |
| `Gcf` | `gcloud compute firewall-rules` |
| `Gci` | `gcloud compute instances` |
| `Gi` | `gcloud iam` |
| `Gk` | `gcloud container` |
| `Gl` | `gcloud logging` |
| `Gp` | `gcloud pubsub` |
| `Gs` | `gcloud sql` |
| `Gu` | `gcloud components update` |

### Chezmoi

`cz` drives this repository; `scz` drives the system source applied to `/`.

| Abbr | Expansion |
|------|-----------|
| `cz` | `chezmoi` |
| `cza` | `chezmoi apply` |
| `czA` | `chezmoi add` |
| `czAe` | `chezmoi add --encrypt` |
| `czd` | `chezmoi diff --recursive --exclude scripts` |
| `cze` | `chezmoi edit` |
| `czs` | `chezmoi status` |
| `czu` | `chezmoi update` |
| `czDd` | `chezmoi dycrypt decrypt` |
| `czDe` | `chezmoi dycrypt encrypt` |
| `scza` | `scz apply` |
| `sczA` | `scz add` |
| `sczAe` | `scz add --encrypt` |
| `sczd` | `scz diff --recursive --exclude scripts` |
| `scze` | `scz edit` |
| `sczs` | `scz status` |
| `sczu` | `scz update` |

`chezmoi` dispatches an unknown subcommand to `chezmoi-<name>`, so its own
completion knows nothing about `dycrypt`. `completions/chezmoi.fish` adds it,
from the option spec of `chezmoi-dycrypt`: the identity types come from the
`decryptPersonal`/`decryptEnterprise` data of `~/.config/chezmoi/chezmoi.yaml`,
the attributes of `-a` chain on a comma, and `-f` offers `data` beside the
directories. The file name comes from the store the command would read - the
`.age` files of `secrets/data/<identity>` for `decrypt`, the plain ones for
`encrypt`, the contents of `--folder` when it is not the data store - and
follows whatever `-i` and `-f` are already on the line. Only names are listed,
never what is inside them. `chezmoi-dycrypt` called directly, and `scz` through
its wrap, get the same rules.

A completion file here only wins while nothing erases the command's
completions afterwards. `config.fish` used to run
`chezmoi completion fish | source` at every interactive start, and that script
opens with `complete -c chezmoi -e`; the erase loads
`completions/chezmoi.fish` first and then wipes what it just registered, so
`dycrypt` never survived. The line is gone - fish autoloads the same script
from `completions/chezmoi.fish` on the first Tab anyway. Any tool that gets a
file in `completions/` has to be taken out of that eager block for the same
reason.

### Other tools

| Abbr | Expansion |
|------|-----------|
| `bk` | `backup_file` |
| `rs` | `restore_file` |
| `listen_ports` | `netstat -tuplen` |
| `open_ports` | `netstat -tuplan` |
| `syncdy` | `rsync --delete -avhz` |

### Anywhere on the line

| Abbr | Expansion |
|------|-----------|
| `!!` | the previous command (`sudo !!`) |
| `!$` | the last argument of the previous command, quoted when it needs it |
| `...` | `../..`, one more level per dot; `..../src` is `../../../src` |

### Subcommands

Expanded only as the first argument of their command, so a file or branch
named `co` after `git add` stays as typed.

| Command | Abbr | Expansion |
|---------|------|-----------|
| `git` | `br` / `ci` / `co` / `st` / `sw` | `branch` / `commit` / `checkout` / `status` / `switch` |
| `kubectl` | `a` / `d` / `e` / `g` / `l` / `x` | `apply -f` / `describe` / `edit` / `get` / `logs` / `exec -it` |
| `docker` | `i` / `l` / `x` | `image` / `logs -f --tail 50` / `exec -it` |

### Per project

A `.fish-abbr` file holds the abbreviations of a project, one
`name expansion…` per line, `#` for comments. They are loaded below its
directory and erased on leaving it, and never take over an abbreviation
defined elsewhere. Enter expands and runs at once, so a file is loaded only
once trusted, and editing it asks for trust again:

| Command | Action |
|---------|--------|
| `dir_abbr` | List what the nearest `.fish-abbr` loaded |
| `dir_abbr trust [-y]` | Show the nearest `.fish-abbr` and trust its content |
| `dir_abbr untrust` | Stop loading it |

## Aliases

Expanded when the command runs, not while typing: they replace a command
rather than shorten one. The editor and modern replacement ones exist only in
an interactive shell, so `fish -c` and fish scripts get the real tools.

### Editor

| Alias | Expansion |
|-------|-----------|
| `vim` | `nvim` (only when Neovim is available) |
| `vimdiff` | `nvim -d` (only when Neovim is available) |
| `nvims` | the stable Neovim from mise, with its own config |

### Pickers

Each lists with fzf, then acts on the pick.

| Command | Action |
|---------|--------|
| `fgcs` | Print the hash of a commit |
| `fgb` | `git switch` to a local or remote branch, listed with how far it is from its upstream; a branch checked out in another worktree takes you to that worktree |
| `fgwt` | `cd` to a worktree of the repository |
| `fgst` | Apply, show or drop a stash, with its diff as preview; dropping asks first |
| `fkctx` | Switch the kubectl context |
| `fkns` | Switch the namespace of the current kubectl context |
| `fkpod` | Follow the logs of, open a shell in, describe or delete a pod; deleting asks first |
| `fdx` | Open a shell in a running container |
| `fcz` | `chezmoi edit` a managed file; encrypted files are not listed, and there is no preview, since rendering a template can read secrets |
| `fGpc` | Switch the GCP project |
| `fGcis` | SSH into an instance |
| `fGciS` | Search instances |

`ctrl-o` then a letter inserts the pick at the cursor instead of acting on it,
in emacs and vi insert mode alike:

| Keys | Inserts |
|------|---------|
| `ctrl-o b` | a branch |
| `ctrl-o h` | the hash of a commit |
| `ctrl-o p` | a pod of the current namespace |
| `ctrl-o d` | a running container |

### Navigation

| Function | Action |
|----------|--------|
| `gR` | `cd` to git root folder |
| `gRu` | `cd` to superproject root if in a submodule, else to the main checkout of the repository |

### Clipboard

Resolved once at startup, per platform.

| Alias | Expansion |
|-------|-----------|
| `copy` | `pbcopy` (macOS), `termux-clipboard-set` (Termux), `wl-copy` (Wayland), `xsel -i -b` (X11) |
| `paste` | `pbpaste` (macOS), `termux-clipboard-get` (Termux), `wl-paste` (Wayland), `xsel -o -b` (X11) |

### Modern replacements

Each is defined only when the replacement is installed.

| Alias | Expansion |
|-------|-----------|
| `cat` | `nvimpager` |
| `ls` | `eza --icons auto --color=always` |
| `ping` | `gping` |
| `top` / `htop` | `btop` |
| `ps` | `procs` |
| `watch` | `viddy` |
| `du` | `dust` |
| `df` | `duf` |
| `curl` | `curlie` |
| `dig` | `q` |
| `less` / `more` | `ov` |
| `fd` | `fdfind` (Debian/Ubuntu only) |
| `mise` | `mise` wrapped in `proot` so it can resolve DNS and TLS (Termux only) |

## Hooks

- **History filter**: `fish_should_add_to_history` keeps out of the history a
  command typed after a space, as fish does by default, and any command that
  carries a credential: an assignment to a variable named like one
  (`GH_TOKEN=…`, `set -gx API_KEY …`), a `--password`/`--token`/`--secret`
  flag with a value, an `Authorization:` header, a `user:password@` URL, or a
  well-known token shape (GitHub, GitLab, Slack, AWS, `sk-…`). Patterns of
  one machine go in `$history_secret_patterns`, from `per_machine.fish` or
  `secret.fish`. A refused command prints a dim note saying so, unless
  `$history_secret_notice` is 0. `history_scrub` finds the entries saved
  before the filter caught them, lists them with the credential masked, and
  deletes them once confirmed (`--dry-run` only lists, `--yes` skips the
  question).
- **Long command notification**: a command running at least
  `$notify_long_command_seconds` (60 by default, 0 turns it off) sends a
  desktop notification when it ends: through kitty while its window is out of
  focus, otherwise `osascript` or `notify-send`, skipped when kitty reports
  the window focused (asked over its remote control, so it also works inside
  zellij). Programs listed in `$notify_long_command_ignore` (editors, pagers,
  `ssh`, TUIs), directories matching a glob of
  `$notify_long_command_ignore_dirs` and SSH sessions never notify, and a
  command the history filter refuses shows only its program name.
- **`notify_me COMMAND…`** runs the command and notifies however long it took,
  also to Telegram when `NOTIFY_TELEGRAM_BOT_TOKEN` and
  `NOTIFY_TELEGRAM_CHAT_ID` are set (in `secret.fish`, never in the
  repository) - so it reaches the phone from an SSH session too. The token
  goes to curl through stdin, out of the process list.
- **Listing on `cd`**: every change of directory lists it with `eza`, unless
  it holds more than `$auto_ls_max_entries` entries (200 by default, 0 lists
  every directory). The first `$auto_ls_readme_lines` lines of its README
  follow (3 by default, 0 for none), and entering a repository shows once its
  branch and distance from upstream (`$auto_ls_git_summary` 0 turns it off).
  It reads refs only, never the working tree: `git status` would run what the
  repository's own config names, such as `core.fsmonitor`, on a mere `cd`.
- **prek**: entering a repository with a `.pre-commit-config.yaml` or
  `prek.toml` installs the prek pre-commit shim, unless it is there already.
