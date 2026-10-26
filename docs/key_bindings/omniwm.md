# OmniWM

The keys come from the bindings in `home/.chezmoitemplates/wm/rules.yaml.tmpl`,
as for [AeroSpace](./aerospace.md), on OmniWM's scrolling columns. OmniWM
takes one key per action, so it has the arrows but not the hjkl twins. OmniWM has no binding modes, so the service and apps
modes of AeroSpace have no counterpart here.

## Modifier keys
- `Super` (Command/⌘) - Main modifier for all keybindings

## Layout management

| Keybind | Action |
|---------|--------|
| `Super+,` | Toggle the workspace layout (scrolling ↔ dwindle) |
| `Super+.` | Toggle fullscreen |
| `Super+/` | Toggle floating ↔ tiling |
| `Super+Shift+Left` | Consume the window into the column |
| `Super+Shift+Right` | Expel the window from its column |
| `Super+Shift+Up` | Move window up in its column |
| `Super+Shift+Down` | Move window down in its column |

## Window focus navigation

| Keybind | Action |
|---------|--------|
| `Super+Left` | Focus window to left |
| `Super+Right` | Focus window to right |
| `Super+Up` | Focus window above |
| `Super+Down` | Focus window below |

## Window moving

| Keybind | Action |
|---------|--------|
| `Alt+Super+Left` | Move window left |
| `Alt+Super+Right` | Move window right |
| `Alt+Super+Up` | Move window up |
| `Alt+Super+Down` | Move window down |

## Window resizing

| Keybind | Action |
|---------|--------|
| `Super+Shift+-` | Shrink the column by 10% |
| `Super+Shift+=` | Grow the column by 10% |

## Workspace management

| Keybind | Action |
|---------|--------|
| `Super+1..9,0` | Switch to workspace `1`-`10` |
| `Super+Shift+1..9,0` | Move window to workspace `1`-`10` |
| `Super+Tab` | Switch to previous workspace (back-and-forth) |
| `Ctrl+Super+Left` / `Ctrl+Super+Right` | Move workspace to the monitor on the left/right |

The workspaces carry the names of the Hyprland ones (`term`, `web`, `mail`,
`doc`, `chat`, `media`, `game`, `sys`, `misc`, `sec`) as labels on OmniWM's
own workspace bar.

## Application launching

OmniWM runs no commands, so Hammerspoon binds these:

| Keybind | Action |
|---------|--------|
| `Super+Return` | Open terminal (kitty + zellij) |
| `Super+E` | Browser, personal profile at home / enterprise profile at the office |
| `Super+Shift+E` | Browser, the other profile |
| `Super+M` | Mail client, personal profile at home / enterprise profile at the office |
| `Super+Shift+M` | Mail client, the other profile |
| `Super+F2` | Launcher (Vicinae) |
| `Ctrl+Super+V` | Clipboard history |
| `Super+P` / `Super+Shift+P` | Type a password / TOTP picked from Bitwarden |

---
