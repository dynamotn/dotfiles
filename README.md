<div align="center">

### Dynamo's dotfiles :house:&nbsp;

#### \> One chezmoi source for every machine I touch :robot:&nbsp;

</div>

<p align="center">
 <a href="https://github.com/dynamotn/dotfiles/stargazers">
  <img alt="Stargazers" src="https://img.shields.io/github/stars/dynamotn/dotfiles?style=for-the-badge&logo=starship&color=C9CBFF&logoColor=D9E0EE&labelColor=302D41"></a>
 <a href="https://github.com/dynamotn/dotfiles/issues">
  <img alt="Issues" src="https://img.shields.io/github/issues/dynamotn/dotfiles?style=for-the-badge&logo=gitbook&color=B5E8E0&logoColor=D9E0EE&labelColor=302D41"></a>
 <a href="https://github.com/twpayne/chezmoi">
  <img alt="Managed with chezmoi" src="https://img.shields.io/badge/managed%20with-chezmoi-F5C2E7?style=for-the-badge&labelColor=302D41"></a>
 <a href="LICENSE">
  <img alt="License" src="https://img.shields.io/badge/license-see%20LICENSE-ABE9B3?style=for-the-badge&labelColor=302D41"></a>
</p>

<p align="center">
  <img alt="macOS desktop: AeroSpace tiling neovim and fish under SketchyBar" src="https://raw.githubusercontent.com/dynamotn/dotfiles/screenshots/macos.jpg" width="100%">
</p>

<!--toc:start-->
- [:book:&nbsp; Overview](#booknbsp-overview)
- [:sparkles:&nbsp; Highlights](#sparklesnbsp-highlights)
- [:camera:&nbsp; Screenshots](#cameranbsp-screenshots)
- [💻 Supported Platforms](#-supported-platforms)
- [:brain:&nbsp; Philosophy](#brainnbsp-philosophy)
- [:wrench:&nbsp; Rules](#wrenchnbsp-rules)
- [:inbox_tray:&nbsp; Installation](#inboxtraynbsp-installation)
- [:file_folder:&nbsp; Repository layout](#file_foldernbsp-repository-layout)
- [:scroll:&nbsp; Cheatsheet](#scrollnbsp-cheatsheet)
- [:package:&nbsp; Tools & Packages](#packagenbsp-tools-packages)
  - [via my `dytoy` scripts](#via-my-dytoy-scripts)
  - [via `dyai` for AI agents](#via-dyai-for-ai-agents)
  - [via Mason of neovim](#via-mason-of-neovim)
- [:books:&nbsp; Guides](#booksnbsp-guides)
- [:hammer:&nbsp; Development](#hammernbsp-development)
<!--toc:end-->

## :book:&nbsp; Overview

This repository holds all my dotfiles and working configuration, managed by
[chezmoi](https://github.com/twpayne/chezmoi). The same source sets up a
Gentoo workstation, an Arch laptop, a MacBook, a phone running Termux and a
throwaway container. Every machine answers a handful of questions once
(GUI server, window manager, browser, mail client, multiplexer...), and
templates render only what fits it.

## :sparkles:&nbsp; Highlights

| Area | What you get |
|-|-|
| Shell | [fish](https://fishshell.com) with a custom prompt, abbreviations and helper functions |
| Editor | [Neovim](https://neovim.io), kept in its own submodule, with LSP, DAP and linters from Mason |
| Terminal | [kitty](https://sw.kovidgoyal.net/kitty/) and [Zellij](https://zellij.dev) (or tmux) |
| Linux desktop | [niri](https://github.com/YaLTeR/niri) or [Hyprland](https://hyprland.org) on Wayland, with the [Noctalia](https://github.com/noctalia-dev/noctalia-shell) shell |
| macOS desktop | [AeroSpace](https://github.com/nikitabobko/AeroSpace) or OmniWM, with [SketchyBar](https://github.com/FelixKratz/SketchyBar) and Hammerspoon |
| Apps | Zen Browser or Firefox and Betterbird or Thunderbird, each with separate personal and work profiles; [yazi](https://yazi-rs.github.io), lazygit, btop, k9s, mpv... |
| Theme | [Catppuccin](https://catppuccin.com) everywhere, from the terminal palette to the wallpaper |
| Secrets | [age](https://age-encryption.org), with a separate identity for each purpose, decrypted only on machines that need it |
| Tools | `dytoy` installs the same tool set on every OS from one YAML list |
| AI agents | `dyai` shares skills, subagents, MCP servers and policy across Claude, Gemini, Copilot, opencode, Codex and more |
| System | Gentoo kernel configs, sysctl tuning, toolbox container images and a Lima image for Arch Linux ARM |

## :camera:&nbsp; Screenshots

### macOS — AeroSpace + SketchyBar

![macOS desktop: AeroSpace tiling neovim and fish under SketchyBar](https://raw.githubusercontent.com/dynamotn/dotfiles/screenshots/macos.jpg)

### Gentoo Linux — niri + Noctalia

![Gentoo desktop: niri columns with neovim and fish over a Catppuccin wallpaper, Noctalia bar on the right](https://raw.githubusercontent.com/dynamotn/dotfiles/screenshots/linux.jpg)

> [!NOTE]
> The screenshots live on the orphan
> [`screenshots`](https://github.com/dynamotn/dotfiles/tree/screenshots)
> branch, so the images never weigh on a clone of `main`.

## 💻 Supported Platforms

|Key|Definition|
|-|-|
|✅|Fully supported|
|❔|Limited supported|
|❌|Not supported|
|🧪|Experimental|

### Architecture

|OS/Distro|amd64|armv8 (arm64)|armv7 (arm)|Note|
|-|-|-|-|-|
|Gentoo|✅|✅|❔| |
|Arch Linux|✅|✅|❔|Included ARM version|
|Ubuntu|✅|❔|❔|Only from 24.04 LTS version|
|Alpine|✅|✅|❔|Only for container|
|Fedora|❔|❔|❔|Bootstrap only, `dytoy` installs no packages|
|MacOS|❌|✅|||
|Android|❔|✅|❌|Not need to rooted|
|Windows|❌|❌|❌|Some tools on WSL can work, but not tested|

### GUI server protocols

- Linux Wayland: ✅
- Linux X11: ❔
- MacOS Quartz Compositor: ✅

## :brain:&nbsp; Philosophy

- **Everything must be under control:** every configuration lives in this
  repository, plain text and credentials alike (encrypted), with no
  exception.
- **Everything must be easy to set up or change:** initializing, editing,
  removing, extending and updating anything stays simple.
- **Everything must be automated, with the fewest manual steps before
  setup:** a new device, like the old one or not, should not pull me away
  from other work with hand-made steps.
- **Everything must be dynamic, everywhere:** it adapts to every machine and
  place, without tying me to one tool or one way of deploying.
- **Everything must share the same pastel palette, in harmony:** one colour
  scheme ([Catppuccin](https://catppuccin.com)) from the terminal to the
  wallpaper.
- **Everything must work together:** a tool that does not fit with the rest
  is dropped.

## :wrench:&nbsp; Rules

- Manage all configurations by only chezmoi, not use any other tool
(`dotbot`, `comtrya`, `stow`...) or IaC tool (`ansible`, `nix`...).
- Use script and template of chezmoi to generate and run anything.
- Use YAML to store shared config
- Use age with separated identity for each purpose
- Manage my home folders, some of OS configurations across multiple machines and working-in-progress folders
- Must convert configurations of a tool to use Git submodule as a part
of dotfiles, if match any of below conditions:
  - Not existed in any machine, and has large disk usage (>=1MiB)
  - Can be separated as a Git repository to get more stargazers,
  or to contribute from other folks :)
  - Conflict with this repository's LICENSE

## :inbox_tray:&nbsp; Installation

Run these commands:

```sh
curl -sSL https://raw.githubusercontent.com/dynamotn/dotfiles/main/scripts/prerequisite.sh | sh -
git clone https://github.com/dynamotn/dotfiles ~/Dotfiles
bash ~/Dotfiles/scripts/setup.sh
```

`prerequisite.sh` installs what chezmoi needs on Gentoo, Arch, Ubuntu/Debian,
Fedora, Alpine, Termux and macOS. `setup.sh` then fetches chezmoi, age and
yq, asks its questions and applies everything.

Answer questions, and wait to finish all setup scripts. The options of
`setup.sh`, the meaning of every question and the container and Lima images
are described in [setup](docs/setup.md).

> [!NOTE]
>
> - If you aren't me, need to answer no (`n`) for "Do you want to decrypt... secrets?" questions.
> Don't ask me why :)
> - The answers of my own machines are stored in
> [`home/.chezmoidata/machines.yaml`](home/.chezmoidata/machines.yaml), so a
> machine listed there is not asked them again. Its proxy and hostname are
> kept encrypted in `secrets/data/<identity>/machine.yaml.age`.
> - You need to grant "Full Disk Access" permission for terminal apps to fully set up machine

### The questions

| Question | Choices |
|-|-|
| Place | cloud, home, office, mobility |
| Kind | container, pc, laptop, workstation, tablet, mobile, vm, sbc |
| GUI server | CLI-only, Wayland, XOrg, Mac |
| GUI driver | Nvidia, Intel, AMD, Mac, virtual |
| Window manager | Hyprland, niri, AeroSpace, OmniWM, GNOME |
| Browser | Zen Browser, Firefox, none |
| Mail client | Betterbird, Thunderbird, none |
| Terminal multiplexer | Zellij, tmux |

The full list, with defaults, is in
[`home/.chezmoidata/choices.yaml`](home/.chezmoidata/choices.yaml).

## :file_folder:&nbsp; Repository layout

| Path | What it holds |
|-|-|
| [`home/`](home/) | chezmoi source for `$HOME` (`.chezmoiroot` points here) |
| [`root/`](root/) | source for system files applied to `/` |
| [`cascadeur/`](cascadeur/) | chezmoi source rendering this repo's `.gitmodules` |
| [`docker/`](docker/) | Dockerfiles and build script of the toolbox images |
| [`scripts/`](scripts/) | setup, test, kernel, container and Lima scripts, plus bash libraries and the `dyai` submodule |
| [`schemas/`](schemas/) | YAML schemas for `dytoy` and the secrets data (`dyai`'s live in its submodule) |
| [`secrets/`](secrets/) | age-encrypted secrets |
| [`silos/`](silos/) | shortcuts to the configs I open most, and large submodules |
| [`docs/`](docs/) | guides, commands and key bindings |

## :scroll:&nbsp; Cheatsheet

### Key bindings

| Scope | Sheet |
|-|-|
| Terminal | [kitty](docs/key_bindings/kitty.md), [fish](docs/key_bindings/fish.md), [neovim](docs/key_bindings/neovim.md) |
| Linux window managers | [niri](docs/key_bindings/niri.md), [Hyprland](docs/key_bindings/hyprland.md) |
| macOS | [macOS](docs/key_bindings/macos.md), [AeroSpace](docs/key_bindings/aerospace.md), [OmniWM](docs/key_bindings/omniwm.md) |

All sheets: [key bindings](./docs/key_bindings/)

### Commands

See [commands](./docs/commands/), starting with the [fish](docs/commands/fish.md)
functions and abbreviations.

## :package:&nbsp; Tools & Packages

### via my `dytoy` scripts

One YAML list says which tool comes from where — OS package manager, GitHub
release, mise, chezmoi external — and `dytoy` installs it the same way on
every platform. See [dytoy](docs/dytoy.md).

### via `dyai` for AI agents

`dyai` manages skills, subagents, MCP servers, plugins, hooks and policy for
every supported agent, the way `mise` manages tools: a shared baseline, plus
presets a project pulls in on demand. See [dyai](scripts/lib/dyai/docs/dyai.md).

### via Mason of neovim

All LSP servers, debuggers, formatters, linters when I used with `neovim`
will be managed by [mason plugin](https://github.com/williamboman/mason.nvim/).
I also have a custom registry in `neovim` config.

## :books:&nbsp; Guides

| Guide                          | Covers                                                |
|--------------------------------|-------------------------------------------------------|
| [architecture](docs/architecture.md) | How the layers, data, hooks and agents fit together |
| [setup](docs/setup.md)         | `setup.sh` options, init questions, machines, images  |
| [secrets](docs/secrets.md)     | age identities, `chezmoi-dycrypt`, secret data layout |
| [dytoy](docs/dytoy.md)         | Installing tools from `dytoy` YAML                    |
| [dyai](scripts/lib/dyai/docs/dyai.md)           | AI agents, presets, MCP servers and skills            |
| [kernel](docs/kernel.md)       | Building the Gentoo kernel with `scripts/kernel.sh`   |
| [tuning](docs/tuning.md)       | System tuning notes                                   |
| [notes](docs/notes.md)         | Odd fixes for specific distributions                  |

## :hammer:&nbsp; Development

Conventions for editing this repository, for humans and agents alike, are in
[AGENTS.md](AGENTS.md). Before committing, run:

```sh
./scripts/test.sh --all        # bats suite and every schema validation
dyshellint <changed scripts>   # shellcheck + shfmt + house rules
pre-commit run --all-files     # incl. betterleaks and detect-private-key
```

`./scripts/test.sh --dytoy`, `--dyai` or `--secrets` runs one schema
validation on its own.
