# Neovim

## Configuration
* LazyVim-based (Neovim 0.11+, Lua)

## Leader Key
* `Space` (main leader key for custom mappings)
## Local Leader
* Available for plugin-specific mappings

## Basic Editing - Smart Delete & Paste

| Keybind | Action |
|---------|--------|
| `<C-c>` | Change word (ciw) |
| `d`, `dd`, `x`, `c`, `s` | Smart delete|
| `v+p` | Paste without copying|

## Command Abbreviations

| Abbr | Expansion |
|------|-----------|
| `W!` | `w!` (force write) |
| `Q!` | `q!` (force quit) |
| `Qa!` | `qa!` (force quit all) |
| `Wq` / `wQ` / `WQ` | `wq` (write and quit) |
| `Wa` | `wa` (write all) |
| `W` | `w` (write) |
| `Q` | `q` (quit) |
| `Qa` | `qa` (quit all) |
| `ww` | `w ! sudo tee % > /dev/null` (sudo write) |

## Tab Navigation

| Keybind | Action |
|---------|--------|
| `<leader><tab>1..9` | Go to Tab 1-9 |

## Language-Specific Keybindings

### Markdown

| Keybind | Action |
|---------|--------|
| `<leader>cp` | Markdown preview |
| `<leader>T` | Open Todo List (Obsidian) |

### Typst

| Keybind | Action |
|---------|--------|
| `<leader>cp` | Typst preview |
| `<leader>cP` | Pin main file |

### Image operations

| Keybind | Action |
|---------|--------|
| `<leader>p` | Paste image from clipboard |

## Terminal & UI

| Keybind | Action |
|---------|--------|
| `<F3>` | Toggle terminal (toggleterm) |

---
