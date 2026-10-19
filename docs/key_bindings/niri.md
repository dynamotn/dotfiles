# niri

The keys follow the [Hyprland ones](./hyprland.md), mapped onto niri's
scrollable columns.

## Modifier keys
- `Super`: Main modifier
- `Alt`: Alternative modifier

## Session control

| Keybind | Action |
|---------|--------|
| `Ctrl+Alt+Delete` | Exit niri |
| `Super+Shift+/` | Show the key binding overlay |

niri reloads its configuration on its own whenever a file changes.

## Application launcher

| Keybind | Action |
|---------|--------|
| `Alt+F2` | Application launcher (same as `Super+F2`) |
| `Super+F2` | Application launcher|

## Workspace navigation

| Keybind | Action |
|---------|--------|
| `Super+1..9,0` | Switch to the named workspace bound to that key |
| `Super+D` | Move current workspace to the next monitor |
| `Super+Ctrl+Left` / `Super+Ctrl+Right` | Move current workspace to the left/right monitor |
| `Super+MouseScroll` | Cycle through workspaces |
| `Super+Tab` | Toggle the overview |

Workspaces are named, not numbered, the same as on Hyprland:

| Key | Workspace |
|-----|-----------|
| `1` | `term` |
| `2` | `web` |
| `3` | `mail` |
| `4` | `doc` |
| `5` | `chat` |
| `6` | `media` |
| `7` | `game` |
| `8` | `sys` |
| `9` | `misc` |
| `0` | `sec` |

## Window management

| Keybind | Action |
|---------|--------|
| `Super+Shift+1..9,0` | Move column to that named workspace, silently |
| `Super+Left` / `Super+Right` | Focus column left/right |
| `Super+Up` / `Super+Down` | Focus window up/down in the column |
| `Alt+Tab` | Focus next column, wrapping around |
| `Super+LMB/RMB` | Move/resize window |
| `Super+Shift+Left` / `Super+Shift+Right` | Shrink/grow column width by 10% |
| `Super+Shift+Up` / `Super+Shift+Down` | Shrink/grow window height by 10% |
| `Alt+F4` | Close active window |
| `Super+.` | Fullscreen |
| `Super+/` | Toggle floating |
| `Super+,` | Cycle preset column widths (1/3, 1/2, 2/3) |
| `Super+;` | Toggle tabbed column |
| `Super+'` | Consume the window into the column on the right, or expel it |

## Applications

| Keybind | Action |
|---------|--------|
| `Super+Return` | Terminal (kitty + zellij) |
| `Super+E` | Browser, personal profile at home / enterprise profile at the office |
| `Super+Q` | Browser, the other profile |
| `Super+M` | Mail client, personal profile at home / enterprise profile at the office |
| `Super+K` | Mail client, the other profile |
| `Super+N` | Control center |
| `Super+Shift+N` | Toggle do not disturb |
| `Alt+N` | Act on the latest notification |
| `Super+J` | Clipboard history |
| `Super+P` | Pick a Bitwarden entry and type its password |
| `Super+O` | Pick a Bitwarden entry and type its TOTP code |
| `Super+L` | Lock session |
| `Super+S` | Screenshot a selected region, then annotate it |
| `Super+Z` | Floating `btop` in kitty |

## Media control

| Keybind | Action |
|---------|--------|
| `XF86AudioRaiseVolume` | Increase volume |
| `XF86AudioLowerVolume` | Decrease volume |
| `XF86AudioMute` | Mute/unmute audio |
| `XF86AudioMicMute` | Mute/unmute microphone |
| `XF86AudioPlay` | Play/pause |
| `XF86AudioPause` | Pause |
| `XF86AudioNext` | Next track |
| `XF86AudioPrev` | Previous track |

---
