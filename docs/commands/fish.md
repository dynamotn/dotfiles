# Fish

Everything below is defined in `home/private_dot_config/fish/`: the `conf.d/`
snippets hold the aliases, `config.fish.tmpl` holds the only real abbreviation.

## Abbreviations

Auto expanded on Space/Enter.

| Abbr | Expansion |
|------|-----------|
| `v` | `vim` (aliased to `nvim` when Neovim is available) |

## Aliases

Expanded when the command runs, not while typing.

### Editor

| Alias | Expansion |
|-------|-----------|
| `vim` | `nvim` (only when Neovim is available) |
| `vimdiff` | `nvim -d` (only when Neovim is available) |

### Docker

| Alias | Expansion |
|-------|-----------|
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

| Alias | Expansion |
|-------|-----------|
| `c` | `docker-compose` |
| `cb` | `docker-compose build` |
| `cl` | `docker-compose logs -f --tail 50` |
| `cpl` | `docker-compose pull` |
| `crs` | `docker-compose restart` |
| `cu` | `docker-compose up` |
| `cx` | `docker-compose exec` |

### Git

| Alias | Expansion |
|-------|-----------|
| `g` | `git` |
| `ga` | `git add` |
| `gai` | `git add -i` |
| `gap` | `git add -p` |
| `gb` | `git branch` |
| `gbd` | `git branch -D` |
| `gbl` | `git blame` |
| `gc` | `git commit -v` |
| `gca` | `git commit --amend` |
| `gcan` | `git commit --amend --no-edit --reset-author` |
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
| `ggs` | `gg --stat` |
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
| `gR` | `cd` to git root folder |
| `gRu` | `cd` to superproject root if in a submodule, else to the main checkout of the repository |
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
| `fgcs` | Pick a commit with fzf |

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

| Alias | Expansion |
|-------|-----------|
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
the directory of a kustomization. `kk` carries its own copy of that last rule:
`--wraps` cannot express "the next word is the argument of `-k`". The
wrappers `grc` installs used to pass their arguments through `eval`, which lost
empty and quoted ones and broke completion for every command they colour
(`kubectl`, `docker`, `systemctl`, …).

### Helm

| Alias | Expansion |
|-------|-----------|
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

| Alias | Expansion |
|-------|-----------|
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
| `fGpc` | Switch project with fzf |
| `fGcis` | SSH into an instance picked with fzf |
| `fGciS` | Search instances with fzf |

### Chezmoi

`cz` drives this repository; `scz` drives the system source applied to `/`.

| Alias | Expansion |
|-------|-----------|
| `cz` | `chezmoi` |
| `cza` | `chezmoi apply` |
| `czA` | `chezmoi add` |
| `czAe` | `chezmoi add --encrypt` |
| `czd` | `chezmoi diff --recursive` |
| `cze` | `chezmoi edit` |
| `czs` | `chezmoi status` |
| `czu` | `chezmoi update` |
| `czDd` | `chezmoi dycrypt decrypt` |
| `czDe` | `chezmoi dycrypt encrypt` |
| `scza` | `scz apply` |
| `sczA` | `scz add` |
| `sczAe` | `scz add --encrypt` |
| `sczd` | `scz diff --recursive` |
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
| `cat` | `bat` |
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
| `cd` | `z` |
| `fd` | `fdfind` (Debian/Ubuntu only) |

### Other tools

| Alias | Expansion |
|-------|-----------|
| `bk` | `backup_file` |
| `mise` | `mise` wrapped in `proot` so it can resolve DNS and TLS (Termux only) |
| `rs` | `restore_file` |
| `listen_ports` | `netstat -tuplen` |
| `open_ports` | `netstat -tuplan` |
| `syncdy` | `rsync --delete -avhz` |
