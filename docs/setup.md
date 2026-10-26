# Setup

How a machine goes from bare to fully configured, and the knobs along the way.

## Steps

1. `scripts/prerequisite.sh` installs what setup cannot install itself: the
   package manager, Git, curl, OpenSSH, Bash, GNU tools and `jq`. It is plain
   POSIX `sh`, so it runs as `curl ... | sh -` on a bare image.
2. `scripts/setup.sh` fetches the `dybatpho` submodule, installs chezmoi,
   renders `home/.chezmoi.yaml.tmpl` with `chezmoi init`, then applies the
   dotfiles in order. On a fresh macOS it re-executes itself with Homebrew
   Bash, since it needs Bash 4.3 or newer.
3. The `home/.chezmoiscripts/` hooks run during apply: submodules, packages
   (`dytoy`), mise tools, then per-tool setup and reloads.
4. The root-owned system layer (`root/`) is applied last through `scz`:
   `/Applications` and `/private` on macOS, the whole tree on Linux. It is
   skipped without root access, and inside a container unless `--system` is
   passed.

## `setup.sh` options

| Option                  | Effect                                                         |
|-------------------------|----------------------------------------------------------------|
| `-l`, `--log-level`     | Log level, default `info`                                      |
| `-d`, `--use-default`   | Take the default answer of every question                      |
| `-i`, `--identities`    | Identities to decrypt, comma separated: `personal` and/or company codes |
| `-s`, `--system`        | Apply the system layer even inside a container                 |

Without a terminal (CI, container builds), every question takes its default.

```sh
bash scripts/setup.sh -d -i personal,F1
```

## Questions

`chezmoi init` asks each question once and stores the answer in
`~/.config/chezmoi/chezmoi.yaml`. Run `chezmoi init --prompt` to answer again.

| Field                        | Asks for                                    |
|------------------------------|---------------------------------------------|
| `code`                       | Machine name                                |
| `place`                      | `cloud`, `home`, `office`, `mobility`       |
| `kind`                       | `container`, `pc`, `laptop`, `workstation`, `tablet`, `mobile`, `vm`, `sbc` |
| `company`                    | Owner company code, for non-home machines   |
| `decryptPersonal`            | Decrypt the `personal` identity's secrets   |
| `decryptEnterprise`          | Company identities to decrypt               |
| `guiServer`                  | `W` Wayland, `X` XOrg, `M` Mac, `0` CLI-only |
| `guiDriver`                  | `N` Nvidia, `I` Intel, `A` AMD, `M` Mac, `V` virtual |
| `guiWinManager`              | `H` hyprland, `N` niri, `A` aerospace, `O` omniwm, `G` gnome |
| `languages`                  | Input method languages: `vi`, `ja`, `zh`    |
| `browser`                    | `Z` Zen, `F` Firefox, or none               |
| `browserEnterpriseProfiles`  | Company browser profiles to decrypt         |
| `mailClient`                 | `B` Betterbird, `T` Thunderbird, or none    |
| `mailEnterpriseProfiles`     | Company mail profiles to decrypt            |
| `terminalMultiplexer`        | `Z` Zellij, `T` tmux                        |
| `hasSound`, `hasBluetooth`, `hasWifi` | Hardware present                  |
| `preferGitSSH`               | Clone over SSH instead of HTTPS             |
| `darkMode`                   | Dark theme                                  |

The options and defaults live in
[`home/.chezmoidata/choices.yaml`](../home/.chezmoidata/choices.yaml), the
company codes in
[`home/.chezmoidata/companies.yaml`](../home/.chezmoidata/companies.yaml).
`DOTFILES_KIND=<kind>` overrides `kind` for image builds and provisioning.

## Known machines

A machine listed by its `code` in
[`home/.chezmoidata/machines.yaml`](../home/.chezmoidata/machines.yaml) is not
asked the fields stored there. Only public answers belong in that file
(checked by `schemas/machines.schema.yaml`); the proxy and hostname are kept
encrypted per identity, see [secrets](./secrets.md).

To add a machine, add an entry under `machines:` with the fields to pin, then
run `./scripts/test.sh --all` to validate it.

## Container images

`scripts/docker.sh <image>` builds a toolbox image from
[`docker/`](../docker/). It needs `docker`, `gomplate` and `GITHUB_TOKEN` in
the environment.

| Image             | Base   | Secrets                       |
|-------------------|--------|-------------------------------|
| `public`          | Alpine | none                          |
| `personal`        | Alpine | `personal` identity           |
| `personal-arch`   | Arch   | `personal` identity           |
| `enterprise-<CODE>` | Alpine | that company's identity and SSL certificate |

## Lima image

`scripts/lima-image.sh` builds an Arch Linux ARM (aarch64) cloud image for the
Lima templates: it boots a throwaway Ubuntu VM, runs
`scripts/lima-image-build.sh` inside to pacstrap the system, and links the
result as `Arch-Linux-aarch64-cloudimg-latest.qcow2`.

| Option            | Effect                                                   |
|-------------------|----------------------------------------------------------|
| `-o`, `--output`  | Image directory, default `~/.local/share/lima/images`    |
| `-b`, `--builder` | Builder VM name, default `alarm-builder`                 |
| `-k`, `--keep`    | Keep the builder VM afterwards                           |
