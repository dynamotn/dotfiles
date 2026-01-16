# Fish shell
## Key binding mode
 VI key bindings enabled

Fish shell uses Vi-style key bindings for command line editing with additional custom keybindings for enhanced productivity.

## Custom key bindings

| Keybind | Action |
|---------|--------|
| `Tab` | FZF complete/autocomplete |
| `Ctrl+R` | Search command history with FZF |
| `Ctrl+F` | Search files with FZF |
| `Ctrl+T` | Change directory with FZF |
| `.` | Auto-expand dot (last directory) |
| `!` | Auto-expand bang (history expansion) |
| `$` | Auto-expand last argument |
| `Space` | Show context (`canaudua` prompt context on space) |
| `Enter/Return` | Execute command with transient prompt |
| `Backspace/⌫` | Smart backspace with auto-pair awareness |
| `(`, `[`, `{`, `"`, `'` | Auto-pair matching brackets/quotes |

## Vi mode navigation

- `Esc` - Enter normal mode
- `i` - Insert mode
- `a` - Append mode
- `h/j/k/l` - Move cursor (left/down/up/right)
- `w` - Move forward by word
- `b` - Move backward by word
- `$` - Move to end of line
- `0` - Move to start of line

## Vi mode editing

| Keybind | Action |
|---------|--------|
| `dd` | Delete line |
| `d$` | Delete from cursor to end |
| `d0` | Delete from cursor to start |
| `x` | Delete character |
| `X` | Delete previous character |
| `u` | Undo |
| `Ctrl+R` | Redo |

---
