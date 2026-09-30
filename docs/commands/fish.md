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
| `gdb` | `git branch -D` |
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
| `gv` | `git mv` |
| `gw` | `git worktree` |
| `fgcs` | Pick a commit with fzf |

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

### Helm

| Alias | Expansion |
|-------|-----------|
| `h` | `helm` |
| `hd` | `helm-docs` |
| `hdel` | `helm delete` |
| `hdu` | `helm dependency update` |
| `hg` | `helm get values` |
| `hl` | `helm ls` |
| `hs` | `helm secrets` |
| `hu` | `helm upgrade --install` |

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
