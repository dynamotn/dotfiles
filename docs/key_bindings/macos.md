# macOS

## Modifier keys

I changed modifier keys from origin key to have new effect

| Origin | New effect |
|--------|-----------|
| Capslock | Ctrl |
| Ctrl | Globe or Fn |
| Option | Option |
| Command | Command |
| Globe | Ctrl |

*Combine modifier codes by adding them together*

## Focus navigation

| Keybind | Action |
|---------|--------|
| `Control+F2` | Move focus to menu bar |
| `Control+F3` | Move focus to Dock |
| `Control+F4` | Move focus to active/next window |
| `Control+F5` | Move focus to window toolbar |
| `Control+F6` | Move focus to floating window |
| `Control+F8` | Move focus to status menus |

## Screenshot

| Keybind | Action |
|---------|--------|
| `Command+S` | Copy selected area to clipboard |
| `Command+Shift+S` | Save selected area to file |

## Mission control

| Keybind | Action |
|---------|--------|
| `F11` | Show Desktop |
| `Control+Left` | Go to left space |
| `Control+Right` | Go to right space |
| `Control+Up` | Show Mission control |
| `Control+Down` | Show Application windows |

## Input source & language

| Keybind | Action |
|---------|--------|
| `Command+Option+Space` | Select previous input source |
| `Command+Option+Shift+Space` | Select next input source |

## Application switching

| Keybind | Action |
|---------|--------|
| `Command+Tab` | Switch to next application |
| `Command+Shift+Tab` | Switch to previous application |
| `Option+Tab` | Same as `Alt+Tab` on Windows and Linux |

## Dock & hidden apps

| Keybind | Action |
|---------|--------|
| `Command+Option+D` | Toggle Dock hiding |

## Quick actions & common shortcuts

| Action | Keybind |
|--------|---------|
| Force Quit Application | `Command+Option+Esc` |
| Lock Screen | `Control+Command+Q` |
| Undo | `Command+Z` |
| Redo | `Command+Shift+Z` |
| Select All | `Command+A` |
| Cut | `Command+X` |
| Copy | `Command+C` |
| Paste | `Command+V` |

## Vicinae

Bound by Hammerspoon, since Vicinae has no global hotkey of its own on macOS.

| Keybind | Action |
|---------|--------|
| `Command+F2` | Toggle Vicinae |
| `Ctrl+Command+V` | Clipboard history |
| `Command+P` | Pick a Bitwarden entry and type its password |
| `Command+O` | Pick a Bitwarden entry and type its TOTP code |

## Hammerspoon

| Keybind | Action |
|---------|--------|
| `Command+Ctrl+Shift+Space` | Reset keyboard input source to US |

## External monitors

Bound by Hammerspoon under AeroSpace and OmniWM alike, over DDC/CI with
`dymonitor` (m1ddc, Apple silicon only) on every monitor that answers; the
outcome shows as an alert.

| Keybind | Action |
|---------|--------|
| `Command+Option+=` / `Command+Option+-` | Raise/lower the brightness by 10 |
| `Command+Option+Shift+=` / `Command+Option+Shift+-` | Raise/lower the contrast by 10 |
| `Command+Option+1` | Input source DisplayPort 1 |
| `Command+Option+2` | Input source DisplayPort 2 |
| `Command+Option+3` | Input source HDMI 1 |
| `Command+Option+4` | Input source HDMI 2 |
| `Command+Option+5` | Input source USB-C |

---
