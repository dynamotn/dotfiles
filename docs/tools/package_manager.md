# Terminal applications
| Tool                   | Purpose                                                | Used in                                   |
|------------------------|--------------------------------------------------------|-------------------------------------------|
| `git`                  | Source version control system                          | Prerequisite                              |
| `neovim`               | My love editor, and IDE in my eyes                     | `modules/neovim`                          |
| `fish`                 | Smart command line shell                               | `modules/fish`                            |
| `tmux`                 | Terminal multiplexer                                   | `modules/tmux`                            |
| `grc`                  | Colorise for some GNU/Linux commands                   | `modules/fish`                            |
| `tar`, `unzip`, `gzip` | Uncompress file                                        | Prerequisite, in `home/dot_config/dynamo` |
| `tree-sitter`          | Parser generator tool for syntax                       | `modules/neovim`                          |
| `podman`               | Manage containers and pods, alternative of docker      | DevOps tools                              |
| `tshark`               | CLI of Wireshark, network packet analysis              | Miscellaneous                             |


# Both X and Wayland applications
| Tool          | Purpose                                           | Used in                 |
|---------------|---------------------------------------------------|-------------------------|
| `kitty`       | Terminal emulator, support ligature fonts and GPU | `home/dot_config/kitty` |
| `firefox`     | Web browser                                       | `modules/firefox`       |
| `thunderbird` | Email client                                      | `modules/thunderbird`   |

# X server applications
| Tool            | Purpose                                            | Used in                                                        |
|-----------------|----------------------------------------------------|----------------------------------------------------------------|
| `xdg-user-dirs` | Manage well-known user directories                 | Prerequisite for GUI applications with X                       |
| `ibus-bamboo`   | Vietnamese input method for Ibus                   | `home/dot_config/ibus-bamboo`                                  |
| `awesomewm`     | AwesomeWM, window manager for X                    | `modules/awesome`                                              |
| `redshift`      | Adjusts the color temperature of screen            | `modules/awesome`                                              |
| `xsel`          | Get and set contents of X selection, eg: clipboard | Frequently used tools, in `modules/tmux` and `modules/awesome` |
| `rofi`          | Application launcher, simple switcher              | `modules/awesome`                                              |
| `picom`         | Compositor for X11                                 | `modules/awesome`                                              |
| `xdotool`       | Simulate keyboard input for X11                    | `modules/fish`                                                 |

# Wayland server applications
| Tool           | Purpose                               | Used in                        |
|----------------|---------------------------------------|--------------------------------|
| `fcitx-bamboo` | Vietnamese input method for Fcitx     | `home/dot_config/fcitx-bamboo` |
| `hyprland`     | Window manager for Wayland            | `modules/hyprland`             |
| `eww`          | Widgets and status bar                | `home/dot_config/eww`          |
| `wofi`         | Application launcher, simple switcher | `modules/hyprland`             |
| `wtype`        | Simulate keyboard input for Wayland   | `modules/fish`                 |
| `swww`         | Animated wallpaper daemon             | `modules/hyprland`             |
