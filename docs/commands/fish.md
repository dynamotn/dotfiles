# Fish
## Command abbreviations & aliases

 Auto expanded on Space/Enter

### Editor

| Abbr | Expansion |
|------|-----------|
| `v` | `vim` (or `nvim` if available) |

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
| `dx` | `docker exec -it` |

### Docker Compose
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
| `gap` | `git add -p` |
| `gb` | `git branch` |
| `gbl` | `git blame` |
| `gc` | `git commit -v` |
| `gca` | `git commit --amend` |
| `gcan` | `git commit --amend --no-edit --reset-author` |
| `gcl` | `git clean -df` |
| `gco` | `git checkout` |
| `gcp` | `git cherry-pick` |
| `gd` | `git diff` |
| `gdc` | `git diff --cached` |
| `gf` | `git fetch` |
| `gfa` | `git fetch --all -p` |
| `gfu` | `git fetch --unshallow` |
| `gg` | `git log --graph` |
| `ggp` | `git log -p` |
| `ggs` | `git log --stat` |
| `gl` | `git pull` |
| `gm` | `git merge --ff` |
| `gmc` | `git merge --continue` |
| `gmt` | `git mergetool` |
| `gn` | `git clone --recursive --depth 1` |
| `gnb` | `git checkout -b` |
| `gp` | `git push` |
| `gpo` | `git push -u origin` |
| `gpt` | `git push --tags` |
| `gR` | `cd` to git root folder |
| `grb` | `git rebase` |
| `grbi` | `git rebase -i` |
| `grh` | `git reset --hard` |
| `grm` | `git remote` |
| `grs` | `git reset --soft` |
| `grv` | `git revert` |
| `gs` | `git status` |
| `gsh` | `git show` |
| `gsm` | `git submodule` |
| `gsn` | `git snapshot` |
| `gst` | `git stash` |
| `gsu` | `git submodule update --init --recursive --remote` |
| `gt` | `git tag` |
| `gv` | `git mv` |
| `gw` | `git whatchanged` |

### Kubectl

| Abbr | Expansion |
|------|-----------|
| `k` | `kubectl` |
| `ka` | `kubectl apply -f` |
| `kc` | `kubectl create` |
| `kd` | `kubectl describe` |
| `kdel` | `kubectl delete` |
| `ke` | `kubectl edit` |
| `kg` | `kubectl get` |
| `kl` | `kubectl logs` |
| `klf` | `kubectl logs -f --tail 50` |
| `kr` | `kubectl rollout` |
| `kx` | `kubectl exec -it` |
| `kccc` | `kubectl config current-context` |
| `kcdc` | `kubectl config delete-context` |
| `kcsc` | `kubectl config set-context` |
| `kcuc` | `kubectl config use-context` |

### Helm

| Abbr | Expansion |
|------|-----------|
| `h` | `helm` |
| `hdel` | `helm delete` |
| `hdu` | `helm dependency update` |
| `hg` | `helm get values` |
| `hl` | `helm ls` |
| `hu` | `helm upgrade --install` |

### Chezmoi

| Abbr | Expansion |
|------|-----------|
| `cz` | `chezmoi` |
| `cza` | `chezmoi apply` |
| `czs` | `chezmoi status` |
| `czu` | `chezmoi update` |

### Other tools

| Abbr | Expansion |
|------|-----------|
| `bk` | `backup_file` |
| `rs` | `restore_file` |
| `listen_ports` | `netstat -tuplen` |
| `open_ports` | `netstat -tuplan` |
| `syncdy` | `rsync --delete -avhz` |
