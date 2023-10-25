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

## :book:&nbsp; Overview

This repository contains all my dotfiles managed by [chezmoi](https://github.com/twpayne/chezmoi).
Please note that this is my own personal dotfiles for Linux and Android (Termux).

## :brain:&nbsp; Philosophy

- Everything must be under control
- Everything must be easy to initial or change
- Everything must be automatically, with few manual steps before setup
- Everything must be dynamic, on every places
- Everything must have same pastel, with harmony

## :wrench:&nbsp; Rules

- Manage all configurations by only chezmoi, not use any other tool (dotbot, comtrya, stow...) or IaC tool (ansible, nix...). Use script and template of chezmoi to do anything.
- Manage my home folders, and some of OS configurations across multiple machine
- Must convert configurations of a tool to use Git submodule as a part of dotfiles, if match any of below conditions:
  - Not existed in any machine, and has large disk usage (>=1MiB)
  - Can be separated as a Git repository to get more stargazers, or to contribute from other guys :)
  - Conflict with this repository's LICENSE

## :camera:&nbsp; Screenshots
TODO: List all screenshots

## :inbox_tray:&nbsp; Installation
Run these commands:

```sh
curl -sSL https://raw.githubusercontent.com/dynamotn/dotfiles/main/prerequisite.sh | bash -
git clone https://github.com/dynamotn/dotfiles.git # or git clone https://gitlab.com/dynamo-config/dotfiles.git
cd dotfiles
./setup.sh
```

## :scroll:&nbsp; Cheatsheet
TODO: Link to another configs' cheatsheet

## :wrench:&nbsp; Tools & Packages

### Via package manager
See [package_manager](docs/tools/package_manager.md)
### Via chezmoi external
See [chezmoi](docs/tools/chezmoi.md)

### Via Github Release binary
See [release_binary](docs/tools/release_binary.md)
