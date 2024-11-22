# Terminal applications
|Tool|Purpose|Used in|
|----|-------|-------|
|`git`|Source version control system|Prerequisite|
|`neovim`|My love editor, and IDE in my eyes|`silos/neovim`|
|`fish`|Smart command line shell|`silos/fish`|
|`tmux`|Terminal multiplexer|`silos/tmux`|
|`zellij`|Terminal multiplexer|`silos/zellij`|
|`grc`|Colorise for some GNU/Linux commands|`silos/fish`|
|`tar`, `unzip`, `gzip`,`bzip2`|Uncompress file|Prerequisite, in `home/dot_config/dynamo`|
|`tree-sitter`|Parser generator tool for syntax|`silos/neovim`|
|`tshark`|CLI of Wireshark, network packet analysis|Network tool|
|`nc`|TCP/IP swiss army knife|`silos/eww`|
|`cava`|Audio visualizer|Multimedia tool|
|`playerctl`|Control media players that implement the MPRIS|Multimedia tool|

# Both X and Wayland applications
|Tool|Purpose|Used in|
|----|-------|-------|
|`kitty`|Terminal emulator, support ligature fonts and GPU|`home/dot_config/kitty`|
|`firefox`|Web browser|`silos/firefox`|
|`thunderbird`|Email client|`silos/thunderbird`|
|`nvtop`|Monitor resources of GPU|`silos/hyprland`, `silos/awesome`|
|`obsidian`|Note-taking app|`silos/hyprland`|
|`libnotify`|Library for sending desktop notifications to a notification daemon|Miscellaneous|
|[sonyheadphones](https://github.com/Plutoberth/SonyHeadphonesClient)|Control Sony Headphones|Multimedia tool|

# X server applications
|Tool|Purpose|Used in|
|----|-------|-------|
|`xdg-user-dirs`|Manage well-known user directories|Prerequisite for GUI applications with X|
|`ibus-bamboo`|Vietnamese input method for Ibus|`home/dot_config/ibus-bamboo`|
|`awesomewm`|AwesomeWM, window manager for X|`silos/awesome`|
|`redshift`|Adjusts the color temperature of screen|`silos/awesome`|
|`xsel`|Get and set contents of X selection, eg: clipboard|Frequently used tool, in `silos/tmux` and `silos/awesome`|
|`rofi`|Application launcher, simple switcher|`silos/awesome`|
|`picom`|Compositor for X11|`silos/awesome`|
|`xdotool`|Simulate keyboard input for X11|`silos/fish`|
|`lightdm`|LightDM, display manager for X|OS core tool|
|`xss-lock`|Screen locker for X|`silos/awesome`|
|`flameshot`|Screen capturing and editing snapshot tool for X|`silos/awesome`|

# Wayland server applications
|Tool|Purpose|Used in|
|----|-------|-------|
|`fcitx-bamboo`|Vietnamese input method for Fcitx|`home/dot_config/fcitx-bamboo`|
|`hyprland`|Window manager for Wayland|`silos/hyprland`|
|`hyprshade`|Adjusts the color temperature of screen|`silos/hyprland`|
|`eww`|Widgets and status bar|`home/dot_config/eww`|
|`wofi`|Application launcher, simple switcher|`silos/hyprland`|
|`wtype`|Simulate keyboard input for Wayland|`silos/fish`|
|`swww`|Animated wallpaper daemon|`silos/hyprland`|
|`greetd`|GreetD, display manager for Wayland|OS core tool|
|`swaylock`|Screen locker for Wayland|`silos/hyprland`|
|`swappy`|Editing snapshot tool for Wayland|`silos/hyprland`|
|`grim`|Screen capturing tool for Wayland|`silso/hyprland`|
|`slurp`|Selecting region tool for Wayland|`silos/hyprland`|
|`swaync`|Notification center for Wayland|Miscellaneous|
|`rust`|Compiler and library for Rust|Prerequisite for cargo installation|
|`go`|Compiler and library for Go|Prerequisite for go installation|
|`wdisplays`|Configure display monitors manually with GUI|Miscellaneous
|

# System applications
|Tool|Purpose|Used in|
|----|-------|-------|
|`ssh`|SSH client|DevOps tool|
|`nftables`|Netfilter framework|Security tool|
|`pam-u2f`|PAM U2F module|Security tool|
|`wireguard`|Simple and modern VPN|Security tool|
|`tailscale`|VPN built on Wireguard to connect securely to my machines|Security tool|
|`pipewire`|Audio and video devices framework|Multimedia tool|
|`bluez`|Bluetooth controller|Multimedia tool|
|`kernel`|Linux kernel for OS|OS core tool|
|`cronie`|Run scheduled tasks|OS core tool|
|`fail2ban`|Intrusion prevention software framework|Security tool|
|`auto-cpufreq`|Automatic CPU speed & power optimizer|OS tune tool|
|`grub`|Bootloader for system|OS core tool|
|`docker`|Manage containers|DevOps tool|
|`ollama`|Get up and running LLMs|AI Tool|
