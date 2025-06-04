# Terminal applications

|Tool|Purpose|Used in|
|----|-------|-------|
|[git](https://github.com/git/git)|Source version control system|Prerequisite|
|[neovim](https://github.com/neovim/neovim)|My love editor, and IDE in my eyes|`silos/neovim`|
|[fish](https://github.com/fish-shell/fish-shell)|Smart command line shell|`silos/fish`|
|[tmux](https://github.com/tmux/tmux)|Terminal multiplexer|`silos/tmux`|
|[zellij](https://github.com/zellij-org/zellij)|Terminal multiplexer|`silos/zellij`|
|[grc](https://github.com/garabik/grc)|Colorise for some GNU/Linux commands|`silos/fish`|
|`tar`, `unzip`, `gzip`,`bzip2`|Uncompress file|Prerequisite, in `home/dot_config/dynamo`|
|[tree-sitter](https://github.com/tree-sitter/tree-sitter)|Parser generator tool for syntax|`silos/neovim`|
|[w3m](https://github.com/acg/w3m)|Text-based web browser|Frequently used tool|
|[tshark](https://www.wireshark.org/docs/man-pages/tshark.html)|CLI of Wireshark, network packet analysis|Network tool|
|`nc`|TCP/IP swiss army knife|`silos/eww`|
|[bcc](https://github.com/iovisor/bcc)|Toolkit for IO analysis, networking, monitoring...|SysOps tool|
|[radare2](https://github.com/radareorg/radare2)|Reverse engineering framework|Security tool|
|[lynis](https://github.com/CISOfy/lynis)|Security auditing and hardening tool|Security tool|

# Both Wayland and Mac applications

|Tool|Purpose|Used in|
|----|-------|-------|
|[kitty](https://github.com/kovidgoyal/kitty)|Terminal emulator, support ligature fonts and GPU|`home/dot_config/kitty`|
|[firefox](https://www.mozilla.org/en-US/firefox/)|Web browser|`silos/firefox`|
|[zen-browser](https://zen-browser.app/)|Web browser with modern features|`silos/firefox`|
|[thunderbird](https://www.thunderbird.net/)|Email client|`silos/thunderbird`|
|[nvtop](https://github.com/Syllo/nvtop)|Monitor resources of GPU|`silos/hyprland`, `silos/awesome`|
|[obsidian](https://obsidian.md/)|Note-taking app|`silos/hyprland`|

# Wayland server applications

|Tool|Purpose|Used in|
|----|-------|-------|
|[xdg-user-dirs](https://www.freedesktop.org/wiki/Software/xdg-user-dirs/)|Manage well-known user directories|Prerequisite for GUI applications|
|[hyprland](https://github.com/hyprwm/Hyprland)|Window manager for Wayland|`silos/hyprland`|
|[hyprshade](https://github.com/loqusion/hyprshade)|Adjusts the color temperature of screen|`silos/hyprland`|
|[eww](https://github.com/elkowar/eww)|Widgets and status bar|`home/dot_config/eww`|
|[wofi](https://sr.ht/~scoopta/wofi/)|Application launcher, simple switcher|`silos/hyprland`|
|[wtype](https://github.com/atx/wtype)|Simulate keyboard input for Wayland|`silos/fish`|
|[swww](https://github.com/LGFae/swww)|Animated wallpaper daemon|`silos/hyprland`|
|[greetd](https://sr.ht/~kennylevinsen/greetd/)|GreetD, display manager for Wayland|OS core tool|
|[regreet](https://github.com/rharish101/ReGreet)|ReGreet, greeter for GreetD|OS core tool|
|[hyprlock](https://github.com/hyprwm/hyprlock)|Screen locker for Wayland|`silos/hyprland`|
|[swappy](https://github.com/jtheoof/swappy)|Editing snapshot tool for Wayland|`silos/hyprland`|
|[grim](https://github.com/emersion/grim)|Screen capturing tool for Wayland|`silso/hyprland`|
|[slurp](https://github.com/emersion/slurp)|Selecting region tool for Wayland|`silos/hyprland`|
|[swaync](https://github.com/ErikReider/SwayNotificationCenter)|Notification center for Wayland|Miscellaneous|
|[wdisplays](https://github.com/cyclopsian/wdisplays)|Configure display monitors manually with GUI|Miscellaneous|
|[ibus-bamboo](https://github.com/BambooEngine/ibus-bamboo)|Vietnamese input method for Ibus|`home/dot_config/ibus-bamboo`|
|[fcitx-bamboo](https://github.com/fcitx/fcitx5-bamboo)|Vietnamese input method for Fcitx|`home/dot_config/fcitx-bamboo`|
|[libnotify](https://gitlab.gnome.org/GNOME/libnotify)|Library for sending desktop notifications to a notification daemon|Miscellaneous|

# MacOS GUI applications

|Tool|Purpose|Used in|
|----|-------|-------|
|[sketchybar](https://github.com/FelixKratz/SketchyBar)|Status bar for MacOS|`home/dot_config/sketchybar`|
|[aerospace](https://github.com/nikitabobko/AeroSpace)|Window manager for MacOS|`home/dot_config/aerospace`|
|[raycast](https://www.raycast.com/)|Launcher for everything|Miscellaneous|

# System applications

|Tool|Purpose|Used in|
|----|-------|-------|
|[macos-defaults](https://github.com/dsully/macos-defaults)|Managing macOS defaults declaratively via YAML files|Prerequisite for MacOS|
|`ssh`|SSH client|Network tool|
|[NetworkManager](https://networkmanager.dev/)|Linux network configuration tool suite|Network tool|
|`nftables`|Netfilter framework|Security tool|
|[pam-u2f](https://github.com/Yubico/pam-u2f)|PAM U2F module|Security tool|
|[wireguard](https://www.wireguard.com/)|Simple and modern VPN|Security tool|
|[tailscale](https://github.com/tailscale/tailscale)|VPN built on Wireguard to connect securely to my machines|Security tool|
|[kernel](https://github.com/torvalds/linux)|Linux kernel for OS|OS core tool|
|[cronie](https://github.com/cronie-crond/cronie)|Run scheduled tasks|OS core tool|
|`ntp`|NTP client to sync system clock|OS core tool|
|[fail2ban](https://github.com/fail2ban/fail2ban)|Intrusion prevention software framework|Security tool|
|[auto-cpufreq](https://github.com/AdnanHodzic/auto-cpufreq)|Automatic CPU speed & power optimizer|OS tune tool|
|[grub](https://www.gnu.org/software/grub/)|Bootloader for system|OS core tool|
|[docker](https://docs.docker.com/engine/)|Manage containers|DevOps tool|
|[lima](https://github.com/lima-vm/lima)|Linux VM on MacOS|DevOps tool|
|[ollama](https://github.com/ollama/ollama)|Get up and running LLMs|AI Tool|
|[rust](https://github.com/rust-lang/rust)|Compiler and library for Rust|Prerequisite for cargo installation|
|[go](https://github.com/golang/go)|Compiler and library for Go|Prerequisite for go installation|

# Miscellaneous applications

|Tool|Purpose|Used in|
|----|-------|-------|
|[cava](https://github.com/karlstav/cava)|Audio visualizer|Multimedia tool|
|[playerctl](https://github.com/altdesktop/playerctl)|Control media players that implement the MPRIS|Multimedia tool|
|[pipewire](https://github.com/PipeWire/pipewire)|Audio and video devices framework|Multimedia tool|
|[bluez](https://github.com/bluez/bluez)|Bluetooth controller|Multimedia tool|
|[sonyheadphones](https://github.com/Plutoberth/SonyHeadphonesClient)|Control Sony Headphones|Multimedia tool|
|[mpv](https://github.com/mpv-player/mpv)|Media player|Multimedia tool|
