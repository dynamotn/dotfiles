# Terminal applications
| Tool                   | Purpose                                                | Used in                                 |
|------------------------|--------------------------------------------------------|-----------------------------------------|
| `git`                  | Source version control system                          | Prequisite                              |
| `neovim`               | My love editor, and IDE in my eyes                     | `modules/neovim`                        |
| `fish`                 | Smart command line shell                               | `modules/fish`                          |
| `tmux`                 | Terminal multiplexer                                   | `modules/tmux`                          |
| `ripgrep`              | Alternative to `grep`, with Git integration and faster | Frequently used tools on CLI            |
| `grc`                  | Colorise for some GNU/Linux commands                   | `modules/fish`                          |
| `tar`, `unzip`, `gzip` | Uncompress file                                        | Prequisite, in `home/dot_config/dynamo` |

# Both X and Wayland applications
| Tool    | Purpose                                           | Used in                 |
|---------|---------------------------------------------------|-------------------------|
| `kitty` | Terminal emulator, support ligature fonts and GPU | `home/dot_config/kitty` |

# X server applications
| Tool            | Purpose                                            | Used in                                                        |
|-----------------|----------------------------------------------------|----------------------------------------------------------------|
| `xdg-user-dirs` | Manage well-known user directories                 | Prequisite for GUI applications with X                         |
| `ibus-bamboo`   | Vietnamese input method for Ibus                   | `home/dot_config/ibus-bamboo`                                  |
| `awesomewm`     | AwesomeWM, window manager for X                    | `modules/awesome`                                              |
| `redshift`      | Adjusts the color temperature of screen            | `modules/awesome`                                              |
| `xsel`          | Get and set contents of X selection, eg: clipboard | Frequently used tools, in `modules/tmux` and `modules/awesome` |
| `rofi`          | Application launcher, simple switcher              | `modules/awesome`                                              |

# Wayland server applications
| Tool           | Purpose                               | Used in                        |
|----------------|---------------------------------------|--------------------------------|
| `fcitx-bamboo` | Vietnamese input method for Fcitx     | `home/dot_config/fcitx-bamboo` |
| `hyprland`     | Window manager for Wayland            | `home/dot_config/hypr`         |
| `eww`          | Widgets and status bar                | `home/dot_config/eww`          |
| `wofi`         | Application launcher, simple switcher | `home/dot_config/hypr`         |
