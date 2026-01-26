<div align="center">

### Dynamo's dotfiles :house:&nbsp;

#### \> Managed with chezmoi :robot:&nbsp;

</div>

<p align="center">
 <a href="https://github.com/dynamotn/dotfiles/stargazers">
  <img alt="Stargazers" src="https://img.shields.io/github/stars/dynamotn/dotfiles?style=for-the-badge&logo=starship&color=C9CBFF&logoColor=D9E0EE&labelColor=302D41"></a>
 <a href="https://github.com/dynamotn/dotfiles/issues">
  <img alt="Issues" src="https://img.shields.io/github/issues/dynamotn/dotfiles?style=for-the-badge&logo=gitbook&color=B5E8E0&logoColor=D9E0EE&labelColor=302D41"></a>
</p>

<!--toc:start-->
- [:book:&nbsp; Overview](#booknbsp-overview)
- [:brain:&nbsp; Philosophy](#brainnbsp-philosophy)
- [:wrench:&nbsp; Rules](#wrenchnbsp-rules)
- [:camera:&nbsp; Screenshots](#cameranbsp-screenshots)
- [:inbox_tray:&nbsp; Installation](#inboxtraynbsp-installation)
- [:scroll:&nbsp; Cheatsheet](#scrollnbsp-cheatsheet)
- [:wrench:&nbsp; Tools & Packages](#wrenchnbsp-tools-packages)
  - [via OS package manager](#via-os-package-manager)
  - [via chezmoi external](#via-chezmoi-external)
  - [via Github Release binary](#via-github-release-binary)
  - [via mise](#via-mise)
  - [via Mason of neovim](#via-mason-of-neovim)
<!--toc:end-->

## :book:&nbsp; Overview

This repository contains all my dotfiles and
working configurations managed by [chezmoi](https://github.com/twpayne/chezmoi).

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
|MacOS|❌|✅|||
|Android|❔|✅|❌|Not need to rooted|
|Windows|❌|❌|❌|Some tools on WSL can work, but not tested|

### GUI server protocols
- Linux Wayland: ✅
- Linux X11: ❔
- MacOS Quartz Compositor: ✅
## :brain:&nbsp; Philosophy

- Everything must be under control
- Everything must be easy to initial or change
- Everything must be automatically, with fewest manual steps before setup
- Everything must be dynamic, on every places
- Everything must have same pastel, with harmony

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

## :camera:&nbsp; Screenshots

TODO: List all screenshots

## :inbox_tray:&nbsp; Installation

Run these commands:

```sh
curl -sSL https://raw.githubusercontent.com/dynamotn/dotfiles/main/scripts/prerequisite.sh | bash -
git clone https://github.com/dynamotn/dotfiles ~/Dotfiles
bash ~/Dotfiles/scripts/setup.sh
```

Answer questions, and wait to finish all setup scripts.
> [!NOTE]
>
> - If you aren't me, need to answer no (`n`) for "Do you want to decrypt... secrets?" questions.
> Don't ask me why :)
> - My chezmoi configurations are stored in [my private chezmoi repo for all machines](https://github.com/dynamotn/chezmoi-keeper)
> - You need to grant "Full Disk Access" permission for terminal apps to fully set up machine

## :scroll:&nbsp; Cheatsheet

### Key bindings

See [key bindings](./docs/key_bindings/)

### Commands

See [commands](./docs/commands/)

## :wrench:&nbsp; Tools & Packages

### via my `dytoy` scripts

See [dytoy](docs/dytoy.md)

### via Mason of neovim

All LSP servers, debuggers, formatters, linters when I used with `neovim`
will be managed by [mason plugin](https://github.com/williamboman/mason.nvim/).
I also have a custom registry in `neovim` config.
