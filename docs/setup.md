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
| `-m`, `--machine`       | Name of this machine, which picks its entry of `machines.yaml` |
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
| `terminalMultiplexer`        | `Z` Zellij                                  |
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

## DyBrain jobs

`dybrain-tend <job>` runs one background job of the DyBrain vault
(`$DYBRAIN_VAULT`, default `~/Documents/DyBrain`) from its root. Without the
vault or `uv` it logs a line and exits successfully.

| Job        | When           | Runs (under `99_System/99.03_Scripts/`) |
|------------|----------------|-----------------------------------------|
| `embed`    | daily 01:30    | `dev/vault-embed.py build`              |
| `triage`   | daily 02:00    | `tend/inbox-triage.py`                  |
| `briefing` | daily 06:30    | `tend/briefing.py`, with `~/.config/dybrain/env` sourced when present |
| `weekly`   | Sunday 20:00   | `tend/weekly-draft.py`                  |

The `04-setup-dybrain-jobs` hook schedules them: systemd user timers
(`dybrain-<job>.timer`, `Persistent=true`) on Linux, launchd agents
(`com.dybrain.<job>`, logging to `~/Library/Logs/dybrain-<job>.log`) on macOS.
A run missed while the machine slept happens when it wakes. Other init
systems (OpenRC, runit, Termux) get a `dotfiles:dybrain` block in the user
crontab when `crontab` is installed, logging to
`$XDG_STATE_HOME/dybrain/cron.log`; cron does not catch up a run missed while
the machine was off. Containers get nothing scheduled; run the jobs by hand.

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

The age passphrase comes from the vault through `rbw` (dybw's shim, see
below). Run it from your own terminal: dybw denies a value to a script that an
AI agent started.

## Password manager (dybw)

[dybw](https://github.com/dynamotn/dybw) holds the Bitwarden vault, and
`~/.local/bin/rbw` is a link to it: called as `rbw`, it answers as rbw 1.15
does, so `rbw-pick`, himalaya, `scripts/docker.sh`, `scz` and the fish
completion keep calling `rbw`. It is not installed on Termux nor in
containers, which keep no vault.

| Piece | Where |
|-------|-------|
| `dybw`, `dybw-agent` | downloaded by `dytoy` (`dytoy/dybw.yaml.tmpl`) from a pinned [GitHub release](https://github.com/dynamotn/dybw/releases), checked against its `.sha256`, into `/opt/homebrew/bin` on macOS, `~/.local/bin` on Linux. Builds exist for Linux amd64/arm64 and Apple silicon; an Intel Mac fails the install |
| `~/.config/dybw/config.toml` | `dybw/config.toml.tmpl`: profile `default` from `secrets/data/personal/rbw.yaml.age`, `enterprise-f1` from `enterprise-F1/rbw.yaml.age` (what `RBW_PROFILE=enterprise-f1` picks), and the machine's pinentry |
| the agent at login | `org.dybw.agent` LaunchAgent on macOS (log in `~/Library/Logs/dybw-agent.log`), `dybw-agent.service` with the graphical session on systemd; `04-setup-dybw-agent` loads it. Elsewhere, and whenever none runs, `dybw` starts it on demand |

On macOS dybw sits in the Homebrew prefix on purpose: pinentry-mac is a
Homebrew program the user can write to, and dybw trusts such a pinentry only
from its own install prefix, never from one inside the home (dybw ADR 0008).
The `rbw` link and the agent service wait until dybw is there, so the apply
after the one that installed dybw adds them.

To move to a newer dybw, set `github.version` in `dytoy/dybw.yaml.tmpl` to
the new release tag and apply: the changed definition makes dytoy download
dybw again (`dytoy binary --no-check-installed -t dybw` does it by hand). The
tag is pinned, so a prerelease works as well as a release. Then restart the
agent service on the new binary: `launchctl kickstart -k
gui/$(id -u)/org.dybw.agent` on macOS, `systemctl --user restart dybw-agent`
on Linux, or `dybw agent stop` where none runs (the next `dybw` starts it).

A machine that built dybw from source before keeps that build, as dytoy skips
a tool already on `PATH`: run `dytoy binary --no-check-installed -t dybw`
once, then remove the build's leftovers, `/opt/homebrew/.crates.toml` and
`/opt/homebrew/.crates2.json` on macOS, `cargo uninstall dybw` on Linux.

### Switching a machine from rbw

Once per machine, in a terminal (not from an AI agent):

1. Stop rbw's agent while `rbw` is still rbw: `rbw stop-agent`.
2. `chezmoi diff`, then `chezmoi apply`. It installs the pinentry, downloads
   dybw and writes `~/.config/dybw/config.toml`. A failed download says why
   (no network to GitHub, a checksum mismatch, no build for this machine) and
   leaves rbw as it was; fix it and run `dytoy binary -t dybw`.
3. `chezmoi apply` again: it adds the `rbw` link and loads the agent
   service. `command -v rbw` gives `~/.local/bin/rbw`, `rbw --version` prints
   `rbw 1.15.0`.
4. Log in once per profile with the API key (client id and secret, from the
   web vault's account security settings): `dybw login` asks for both in its
   pinentry, so never put them on a command line. Then unlock:
   `dybw -p default login`, `dybw -p default unlock`; on an F1 machine also
   `dybw -p enterprise-f1 login` and `unlock`.
5. `dybw doctor` passes: socket, agent, config, and the pinentry, which on
   macOS must be accepted by the install-prefix rule.
6. The agent is the service's: `dybw agent stop` in a terminal stops the
   process `launchctl print gui/$(id -u)/org.dybw.agent` or
   `systemctl --user status dybw-agent` shows (`dybw` starts it again on
   demand).
7. Run each caller once and answer the confirmation pinentry asks for:
   - the password and TOTP hotkeys (`rbw-pick`) with no terminal open: the
     unlock and the confirmation must show as GUI prompts;
   - himalaya: `himalaya envelope list`;
   - `scripts/docker.sh personal` up to the build;
   - `scz status`, which unlocks as you and hands root no agent;
   - fish: `rbw <Tab>` and `dybw <Tab>`;
   - a chezmoi template through the shim:
     `chezmoi execute-template '{{ (rbw "<item>").name }}'` prints the item's
     name.
8. Remove rbw: `brew uninstall rbw` on macOS; on Linux
   `rm ~/.local/bin/rbw-agent` (dytoy's rbw binary was replaced by the link);
   `pkg uninstall rbw` on Termux.
9. Remove rbw's leftovers: `~/.config/rbw`, `~/.config/rbw-enterprise-f1`,
   rbw's cache and data directories (`~/.cache/rbw*` and
   `~/.local/share/rbw*` on Linux, `~/Library/Caches/rbw*` on macOS) and, on
   macOS, the links `~/Library/Application Support/rbw` and
   `~/Library/Application Support/rbw-enterprise-f1`.
10. Optional: `dybw unlock add pin`, and on Linux with `pam_bwss` in the PAM
    stack `dybw unlock add login` (the PAM lines are in the bwss README). The
    dotfiles enable neither: enrolment stays on the device.

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
