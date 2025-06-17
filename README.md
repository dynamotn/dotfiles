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

This repository contains all my dotfiles managed by [chezmoi](https://github.com/twpayne/chezmoi).
Please note that this is my own personal dotfiles for Linux
(Gentoo, Arch, Ubuntu), Android (Termux) and MacOS.
I don't use X applications anymore.

## :brain:&nbsp; Philosophy

- Everything must be under control
- Everything must be easy to initial or change
- Everything must be automatically, with fewest manual steps before setup
- Everything must be dynamic, on every places
- Everything must have same pastel, with harmony

## :wrench:&nbsp; Rules

- Manage all configurations by only chezmoi, not use any other tool
(`dotbot`, `comtrya`, `stow`...) or IaC tool (`ansible`, `nix`...).
Use script and template of chezmoi to do anything.
- Manage my home folders, and some of OS configurations across multiple machine
- Must convert configurations of a tool to use Git submodule as a part
of dotfiles, if match any of below conditions:
  - Not existed in any machine, and has large disk usage (>=1MiB)
  - Can be separated as a Git repository to get more stargazers,
  or to contribute from other folks :)
  - Conflict with this repository's LICENSE

## :camera:&nbsp; Screenshots

TODO: List all screenshots

## :inbox_tray:&nbsp; Installation

Run only one command:

```sh
curl -sSL https://raw.githubusercontent.com/dynamotn/dotfiles/main/scripts/prerequisite.sh | bash -
```

Answer questions, and wait to finish all setup scripts. My dotfiles will be located in `$HOME/Dotfiles`

## :scroll:&nbsp; Cheatsheet

TODO: Link to another configs' cheatsheet

## :wrench:&nbsp; Tools & Packages

### via OS package manager

See [package_manager](docs/tools/package_manager.md)

### via chezmoi external

See [chezmoi](docs/tools/chezmoi.md)

### via Github Release binary

See [release_binary](docs/tools/release_binary.md)

### via mise

See [mise](docs/tools/mise.md)

### via Mason of neovim

All LSP servers, debuggers, formatters, linters when I used with `neovim` will be managed by [mason plugin](https://github.com/williamboman/mason.nvim/) and use my [custom registry](https://github.com/dynamotn/mason-registry/)
