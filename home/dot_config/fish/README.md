Feature
========
- My ASCII art of my nickname :D
- Powerline prompt with nerd font
- `ls` with separated color for each file type
- Colored command output with `grc` for `ifconfig`, `docker`, `cat`, `gcc`, `ping`, `netstat`...
- Fish package management with `fisher`
- Fuzzy finder in shell with `fzf`
- Alias with command completion. See [alias section](#alias)

Installation
=============

Clone this repository to ~/.config/fish and run setup.fish
```
rm -rf ~/.config/fish
git clone https://gitlab.com/dynamo-config/fish ~/.config/fish
~/.config/fish/setup.fish
```

Alias
======
| Alias         | Description                                                                                               |
|---------------|-----------------------------------------------------------------------------------------------------------|
| copy          | Copy command output to clipboard                                                                          |
| paste         | Paste clipboard to command line input                                                                     |
| weather       | Show current weather of current network's location                                                        |
| ssht          | SSH to machine and run tmux on it, with `-s` argument is session name of tmux                             |
| load_avg      | Current load average of machine                                                                           |
| syncdy        | Fast rsync command                                                                                        |
| short_ping    | Ping with a few requests                                                                                  |
| fast_ping     | Ping with small interval                                                                                  |
| open_ports    | List all open ports                                                                                       |
| listen_ports  | List all listening ports                                                                                  |
| ip_info       | Get information about IP address                                                                          |
| ip_wan        | Get IP WAN of network client                                                                              |
| ip_lan        | Get IP LAN of network client                                                                              |
| mac_vendor    | Get vendor of MAC address                                                                                 |
| remote_tunnel | Forward port from SSH machine to local, with `-r`, `-l` argument is port of SSH machine and local machine |
| local_tunnel  | Forward port from local to SSH machine, with `-r`, `-l` argument is port of SSH machine and local machine |
| sock_proxy    | Create socks proxy via SSH machine, with `-p` is port of socks proxy in local                             |

#### Git short command
| Alias | Full command                                       |
|-------|----------------------------------------------------|
| g     | `git`                                              |
| ga    | `git add`                                          |
| gap   | `ga -p`                                            |
| gai   | `ga -i`                                            |
| gb    | `git branch`                                       |
| gbl   | `git blame`                                        |
| gc    | `git commit -v`                                    |
| gca   | `gc --amend`                                       |
| gcan  | `gc --amend --no-edit --reset-author`              |
| gcl   | `git clean -df`                                    |
| gco   | `git checkout`                                     |
| gcp   | `git cherry-pick`                                  |
| gd    | `git diff`                                         |
| gdb   | `git branch -D`                                    |
| gdc   | `gd --cached`                                      |
| gf    | `git fetch --all -p`                               |
| gg    | `git log --graph --pretty=format:...`              |
| ggs   | `gg --stat`                                        |
| gl    | `git pull`                                         |
| gm    | `git merge --ff`                                   |
| gmc   | `git merge --continue`                             |
| gmt   | `git mergetool`                                    |
| gn    | `git clone --recursive`                            |
| gnb   | `git checkout -b`                                  |
| gp    | `git push`                                         |
| gpo   | `gp -u origin`                                     |
| grb   | `git rebase`                                       |
| grbi  | `grb -i`                                           |
| grbc  | `grb --continue`                                   |
| grh   | `git reset --hard`                                 |
| grH   | `git reset HEAD`                                   |
| grm   | `git remote`                                       |
| grs   | `git reset --soft`                                 |
| gs    | `git status`                                       |
| gsh   | `git show`                                         |
| gsm   | `git submodule`                                    |
| gsn   | `git snapshot`                                     |
| gst   | `git stash`                                        |
| gsu   | `git submodule update --init --recursive --remote` |
| gt    | `git tag`                                          |
| gw    | `git whatchanged`                                  |
| fgcs  | Fuzzy git commit search with fzf                   |

#### k8s short command
| Alias | Full command                |
|-------|-----------------------------|
| k     | `kubectl`                   |
| ka    | `kubectl apply -f`          |
| kd    | `kubectl delete`            |
| kdc   | `kubectl describe`          |
| ke    | `kubectl edit`              |
| kg    | `kubectl get`               |
| kk    | `kubectl apply -k`          |
| kl    | `kubectl logs`              |
| klf   | `kubectl logs -f --tail 50` |
| kx    | `kubectl exec -it`          |
| h     | `helm`                      |
| hu    | `helm upgrade`              |
| hd    | `helm delete`               |

#### docker short command
| Alias | Full command                       |
|-------|------------------------------------|
| d     | `docker`                           |
| db    | `docker build`                     |
| di    | `docker images`                    |
| dl    | `docker logs -f --tail 50`         |
| dpl   | `docker pull`                      |
| dps   | `docker ps`                        |
| dr    | `docker run`                       |
| drm   | `docker rm`                        |
| drmi  | `docker rmi`                       |
| drs   | `docker restart`                   |
| dsp   | `docker system prune`              |
| dw    | `docker inspect`                   |
| dx    | `docker exec -it`                  |
| c     | `docker-compose`                   |
| cb    | `docker-compose build`             |
| cl    | `docker-compose logs -f --tail 50` |
| cpl   | `docker-compose pull`              |
| crs   | `docker-compose restart`           |
| cu    | `docker-compose up`                |
| cx    | `docker-compose exec`              |

#### gcloud short command
| Alias | Full command                                  |
|-------|-----------------------------------------------|
| G     | `gcloud`                                      |
| fGpc  | Fuzzy gcloud project change with fzf          |
| fGcis | Fuzzy gcloud compute instance search with fzf |

License
========

Copyright © 2019 Tran Duc Nam <me@dynamotn.dev>

The project is licensed under Creative Common BY-NC-SA 4.0.

You can read it online at [here](http://creativecommons.org/licenses/by-nc-sa/4.0/).

Note
=====
- Fish version >= 3.0
