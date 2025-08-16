# Prerequisite

|Tool|Purpose|Used in|
|----|-------|-------|
|[git](https://github.com/git/git)|Source version control system|Prerequisite|
|[yq](https://github.com/mikefarah/yq)|YAML processor|Prerequisite|
|[chezmoi](https://github.com/twpayne/chezmoi)|Manage dotfiles across machines|Prerequisite|
|[age](https://github.com/FiloSottile/age)|Simple file encryption|Prerequisite|
|`tar`, `unzip`, `gzip`, `bzip2`|Uncompress file|Prerequisite, in `home/dot_config/dynamo`|

# System core tools

|[kernel](https://github.com/torvalds/linux)|Linux kernel for OS|OS core tool|
|[cronie](https://github.com/cronie-crond/cronie)|Run scheduled tasks|OS core tool|
|`ntp`|NTP client to sync system clock|OS core tool|
|[auto-cpufreq](https://github.com/AdnanHodzic/auto-cpufreq)|Automatic CPU speed & power optimizer|OS core tool|
|[grub](https://www.gnu.org/software/grub/)|Bootloader for system|OS core tool|

# Everyday terminal applications

|Tool|Purpose|Used in|
|----|-------|-------|
|[neovim](https://github.com/neovim/neovim)|My love editor, and IDE in my eyes|`silos/neovim`|
|[rbw](https://github.com/dynamotn/rbw)|Bitwarden CLI tool||
|[fish](https://github.com/fish-shell/fish-shell)|Smart command line shell|`silos/fish`|
|[tmux](https://github.com/tmux/tmux)|Terminal multiplexer|`silos/tmux`|
|[zellij](https://github.com/zellij-org/zellij)|Terminal multiplexer|`silos/zellij`|
|[grc](https://github.com/garabik/grc)|Colorise for some GNU/Linux commands|`silos/fish`|
|[tree-sitter](https://github.com/tree-sitter/tree-sitter)|Parser generator tool for syntax|`silos/neovim`|
|[w3m](https://github.com/acg/w3m)|Text-based web browser||
|[git-lfs](https://github.com/git-lfs/git-lfs)|Git extension for large files||
|[macos-defaults](https://github.com/dsully/macos-defaults)|Managing macOS defaults declaratively via YAML files|Prerequisite for MacOS|
|[jq](https://github.com/stedolan/jq)|JSON processor|`silos/awesome`|
|[delta](https://github.com/dandavison/delta)|Syntax highlighting pager for git, diff, and grep output|`home/dot_config/git`|
|[bat](https://github.com/sharkdp/bat)|Alternative to `cat` with syntax highlighting and Git integration|Frequently used tool|
|[ov](https://github.com/noborus/ov)|Alternative to `less`, `more`, `tail -f`|Frequently used tool|
|[tspin](https://github.com/bensadeh/tailspin)|Alternative to `tail` with highlighter|Frequently used tool|
|[fd](https://github.com/sharkdp/fd)|Alternative to `find`, simpler and faster|Frequently used tool, in `silos/fish`|
|[eza](https://github.com/eza-community/eza)|Alternative to `ls` with colours, faster|Frequently used tool|
|[ripgrep](https://github.com/BurntSushi/ripgrep)|Alternative to `grep`, with Git integration and faster|Frequently used tool|
|[gping](https://github.com/orf/gping)|Alternative to `ping` with graph|Frequently used tool|
|[wtf](https://github.com/wtfutil/wtf)|Personal information dashboard on CLI|Frequently used tool|
|[zoxide](https://github.com/ajeetdsouza/zoxide)|Alternative to `cd` with smarter|Frequently used tool, in `silos/fish`|
|[mise](https://github.com/jdx/mise)|All-in-one version manager|Frequently used tool, in `silos/fish`|
|[vivid](https://github.com/sharkdp/vivid)|A themeable LS_COLORS generator with database|Frequently used tool|
|[navi](https://github.com/denisidoro/navi)|Cheatsheet CLI tool|Frequently used tool, in `silos/fish`, `silos/tmux`|
|[btop](https://github.com/aristocratos/btop)|Alternative to `htop` and `glances`|Frequently used tool, in `silos/awesome`, `silos/hyprland`|
|[himalaya](https://github.com/soywod/himalaya)|Email CLI tool|Frequently used tool, in `silos/awesome`|
|[smug](https://github.com/ivaaaan/smug)|Tmux session manager|Frequently used tool, in `home/dot_config/smug`|
|[projekt](https://github.com/dynamotn/projekt)|Smart CLI command to manage project folder|Frequently used tool, in `silos/fish`|
|[pomodoro](https://github.com/open-pomodoro/openpomodoro-cli)|CLI command for Pomodoro tracker|Frequently used tool, in `silos/hyprland` and `silos/eww`|
|[procs](https://github.com/dalance/procs)|Alternative to `ps` with colours, tree view...|SysOps tool|
|[rclone](https://github.com/rclone/rclone)|Sync files to and from cloud providers|SysOps tool|
|[viddy](https://github.com/sachaos/viddy)|Alternative to `watch` with colours, diff, time machine...|SysOps tool|
|[dust](https://github.com/bootandy/dust)|Alternative to `du` with more intuitive|SysOps tool|
|[duf](https://github.com/muesli/duf)|Alternative to `df` with colours...|SysOps tool|
|[pulsemixer](https://github.com/GeorgeFilipkin/pulsemixer)|Alternative CLI tool for pavucontrol|Multimedia tool|
|[wol](https://github.com/sabhiram/go-wol)|Wake-on-LAN utility|Miscellaneous|
|[fzf](https://github.com/junegunn/fzf)|Fuzzy finder on CLI|Frequently used tool, in `silos/fish`|
|[lazygit](https://github.com/jesseduffield/lazygit)|TUI for git|Frequently used tool|
|[jira](https://github.com/ankitpokhrel/jira-cli)|Interactive CLI tool with JIRA|Project management tool|
|[glab](https://gitlab.com/gitlab-org/cli)|Interactive CLI tool with Gitlab|Project management tool|
|[gh](https://github.com/cli/cli)|Interactive CLI tool with Github|Project management tool|

# Cross platform GUI applications

|Tool|Purpose|Used in|
|----|-------|-------|
|[kitty](https://github.com/kovidgoyal/kitty)|Terminal emulator, support ligature fonts and GPU|`home/dot_config/kitty`|
|[firefox](https://www.mozilla.org/en-US/firefox/)|Web browser|`silos/firefox`|
|[zen-browser](https://zen-browser.app/)|Web browser with modern features|`silos/firefox`|
|[thunderbird](https://www.thunderbird.net/)|Email client|`silos/thunderbird`|
|[nvtop](https://github.com/Syllo/nvtop)|Monitor resources of GPU|`silos/hyprland`, `silos/awesome`|
|[obsidian](https://obsidian.md/)|Note-taking app|`silos/hyprland`|
|[vmware-horizon-client](https://www.omnissa.com/)|Virtual machine client to remote|Remote control|
|[rustdesk](https://github.com/rustdesk/rustdesk)|Self-hosted remote desktop|Remote control|

# Wayland server applications

|Tool|Purpose|Used in|
|----|-------|-------|
|[xdg-user-dirs](https://www.freedesktop.org/wiki/Software/xdg-user-dirs/)|Manage well-known user directories|Prerequisite for GUI applications|
|[hyprland](https://github.com/hyprwm/Hyprland)|Window manager for Wayland|`silos/hyprland`|
|[hyprshade](https://github.com/loqusion/hyprshade)|Adjusts the color temperature of screen|`silos/hyprland`|
|[hdrop](https://github.com/hyprwm/contrib#hdrop)|Dropdown utilities|`silos/hyrpland`|
|[eww](https://github.com/elkowar/eww)|Widgets and status bar|`home/dot_config/eww`|
|[wofi](https://sr.ht/~scoopta/wofi/)|Application launcher, simple switcher|`silos/hyprland`|
|[wtype](https://github.com/atx/wtype)|Simulate keyboard input for Wayland|`silos/fish`|
|[swww](https://github.com/LGFae/swww)|Animated wallpaper daemon|`silos/hyprland`|
|[greetd](https://sr.ht/~kennylevinsen/greetd/)|GreetD, display manager for Wayland|`root/etc/greetd`|
|[regreet](https://github.com/rharish101/ReGreet)|ReGreet, greeter for GreetD|`root/etc/greetd`|
|[hyprlock](https://github.com/hyprwm/hyprlock)|Screen locker for Wayland|`silos/hyprland`|
|[swappy](https://github.com/jtheoof/swappy)|Editing snapshot tool for Wayland|`silos/hyprland`|
|[grim](https://github.com/emersion/grim)|Screen capturing tool for Wayland|`silso/hyprland`|
|[slurp](https://github.com/emersion/slurp)|Selecting region tool for Wayland|`silos/hyprland`|
|[swaync](https://github.com/ErikReider/SwayNotificationCenter)|Notification center for Wayland|`silos/hyprland`|
|[cliphist](https://github.com/sentriz/cliphist)|Clipboard manager for Wayland|`silos/hyprland`|
|[shikane](https://github.com/hw0lff/shikane)|Automatically detects and configures connected monitors|`silos/hyprland`|
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
|[alt-tab](https://github.com/lwouis/alt-tab-macos)|Windows alt-tab on macOS|Miscellaneous|

# Network tools

|Tool|Purpose|Used in|
|----|-------|-------|
|`ssh`|SSH client|Network tool|
|`netcat`|TCP/IP swiss army knife|Network tool|
|[NetworkManager](https://networkmanager.dev/)|Linux network configuration tool suite|Network tool|
|[tshark](https://www.wireshark.org/docs/man-pages/tshark.html)|CLI of Wireshark, network packet analysis|Network tool|
|[bcc](https://github.com/iovisor/bcc)|Toolkit for IO analysis, networking, monitoring...||
|[trippy](https://github.com/fujiapple852/trippy)|CLI tool for network diagnostic|SysOps tool|
|[termshark](https://github.com/gcla/termshark)|TUI to network packet analysis|Network tool|
|[curlie](https://github.com/rs/curlie)|Alternative to `curl` with the ease of use from `httpie`|Network tool|
|[bandwhich](https://github.com/imsnif/bandwhich)|CLI bandwidth utilization tool|Network tool|
|[q](https://github.com/natesales/q)|Alternative to `dig`|Network tool|
|[speedtest](https://github.com/showwin/speedtest-go)|CLI to test Internet speed|Network tool|
|[websocat](https://github.com/vi/websocat)|Netcat, curl and socat for websocket|Network tool|
|[flarectl](https://github.com/cloudflare/cloudflare-go)|Interactive CLI with Cloudflare|Network tool|
|[oryx](https://github.com/pythops/oryx)|TUI for sniffing network traffic using eBPF|Network tool|
|[httptap](https://github.com/monasticacademy/httptap)|CLI to view HTTP requests per command|Network tool|
|[chisel](https://github.com/jpillora/chisel)|CLI to create TCP/UDP tunnel over HTTP|Network tool|

# Security tools

|Tool|Purpose|Used in|
|----|-------|-------|

|`nftables`|Netfilter framework|Security tool|
|[pam-u2f](https://github.com/Yubico/pam-u2f)|PAM U2F module|Security tool|
|[wireguard](https://www.wireguard.com/)|Simple and modern VPN|Security tool|
|[tailscale](https://github.com/tailscale/tailscale)|VPN built on Wireguard to connect securely to my machines|Security tool|
|[fail2ban](https://github.com/fail2ban/fail2ban)|Intrusion prevention software framework|Security tool|
|[radare2](https://github.com/radareorg/radare2)|Reverse engineering framework|Security tool|
|[lynis](https://github.com/CISOfy/lynis)|Security auditing and hardening tool|Security tool|
|[anti-ddos](https://github.com/anti-ddos/Anti-DDOS)|Anti DDOS|Security tool|
|[kubescape](https://github.com/kubescape/kubescape)|Kubernetes security platform|SecOps tool|
|[terrascan](https://github.com/tenable/terrascan)|IaC security analyzer|SecOps tool|
|[trivy](https://github.com/aquasecurity/trivy)|Security scanner|SecOps tool|
|[amass](https://github.com/owasp-amass/amass)|Network mapping of attack surfaces and external asset discovery|SecOps tool|
|[osintui](https://github.com/wssheldon/osintui)|Open source intelligence tool|Security tool|
|[tsui](https://github.com/neuralinkcorp/tsui)|TUI for Tailscale|Security tool|
|[haiti](https://github.com/noraj/haiti)|Hash type identifier|Security tool|
|[anti-ddos](https://github.com/anti-ddos/Anti-DDOS)|Anti DDOS|Security tool|

# Development tools

|Tool|Purpose|Used in|
|----|-------|-------|
|[shdoc](https://github.com/mbucc/shmig)|Generate documents for Bash shell scripts|Development tool|
|[watchexec](https://github.com/watchexec/watchexec)|Detects modifications and run command|Developer tool|
|[gomplate](https://github.com/hairyhenderson/gomplate)|Template rendering, like jinja|Developer tool|
|[semantic-release](https://github.com/go-semantic-release/semantic-release)|Semantic release|Developer tool|
|[svu](https://github.com/caarlos0/svu)|Get Semantic version|Developer tool|
|[hugo](https://github.com/gohugoio/hugo)|Build static website|Developer tool|
|[trdsql](https://github.com/noborus/trdsql)|CLI execute SQL queries tool|Developer tool|
|[step](https://github.com/smallstep/cli)|CLI tool for PKI systems and workflows|Developer tool|
|[stripe](https://github.com/stripe/stripe-cli)|CLI to build, test Stripe integration|Developer tool|
|[d2](https://github.com/terrastruct/d2)|Diagram as code tool|Developer tool|
|[d2plugin-tala](https://github.com/terrastruct/TALA)|Engine plugin TALA for d2|Developer tool|
|[zrok](https://github.com/openziti/zrok)|Peer-to-peer sharing platform|Developer tool|
|[arduino](https://github.com/arduino/arduino-cli)|CLI to manage Arduino board|IoT tool|
|[posting](https://github.com/darrenburns/posting)|Powerful HTTP client with TUI same as Postman|Developer tool|
|[euporie](https://github.com/joouha/euporie)|Jupyter notebooks in CLI|Developer tool|
|[rust](https://github.com/rust-lang/rust)|Compiler and library for Rust|Prerequisite for cargo installation|
|[go](https://github.com/golang/go)|Compiler and library for Go|Prerequisite for go installation|
|[nodejs](https://github.com/nodejs/node)|JavaScript runtime|LSP servers in `silos/neovim`|
|[deno](https://github.com/denoland/deno)|JavaScript runtime|Markdown preview in `silos/neovim`|
|[uv](https://github.com/astral-sh/uv)|Modern Python package and project manager|Package manager tool|
|[pre-commit](https://github.com/pre-commit/pre-commit)|Framework for manage pre-commit hooks|Developer tool|
|[mkcert](https://github.com/FiloSottile/mkcert)|Make locally-trusted development certificates|Developer tool|
|[scc](github.com/boyter/scc)|Display statistics about code|Miscellaneous|

# DevOps tools

|[docker](https://docs.docker.com/engine/)|Manage containers|DevOps tool|
|[lima](https://github.com/lima-vm/lima)|Linux VM on MacOS|DevOps tool|
|[docker-compose](https://github.com/docker/compose)|Run multi-container applications|DevOps tool|
|[docker-buildx](https://github.com/docker/buildx)|Extended build capabilities for Docker|DevOps tool|
|[lazydocker](https://github.com/jesseduffield/lazydocker)|Interactive TUI with Docker and Compose|DevOps tool|
|[dive](https://github.com/wagoodman/dive)|Explore each layer in Docker images|DevOps tool|
|[diffoci](https://github.com/reproducible-containers/diffoci)|Diff Docker and OCI container images|DevOps tool|
|[k9s](https://github.com/derailed/k9s)|Interactive TUI with Kubernetes cluster|DevOps tool|
|[krew](https://github.com/kubernetes-sigs/krew)|Plugin manager for kubectl|DevOps tool|
|[k0sctl](https://github.com/k0sproject/k0sctl)|Bootstrap and manage k0s cluster|DevOps tool|
|[talosctl](https://github.com/siderolabs/talos)|Bootstrap and manage Talos Linux cluster|DevOps tool|
|[helm-docs](https://github.com/norwoodj/helm-docs)|Generate documents for Helm chart|DevOps tool|
|[kubeconform](https://github.com/yannh/kubeconform)|Validate Kubernetes manifest|DevOps tool|
|[sops](https://github.com/getsops/sops)|Managing secrets in Git repositories|DevOps tool|
|[argocd](https://github.com/argoproj/argo-cd)|Interactive with ArgoCD on Kubenetes cluster|DevOps tool|
|[flux](https://github.com/fluxcd/flux2)|Interactive with Flux on Kubenetes cluster|DevOps tool|
|[fly](https://github.com/superfly/flyctl)|CLI tool for cloud application on fly.io with container|DevOps tool|
|[terraform](https://github.com/hashicorp/terraform)|IaC tool for building, changing, and versioning infrastructure|DevOps tool|
|[terragrunt](https://github.com/gruntwork-io/terragrunt)|Wrapper for Terraform to provide extra tool|DevOps tool|
|[terraformer](https://github.com/GoogleCloudPlatform/terraformer)|Generate Terraform from existing infrastructure|DevOps tool|
|[terraform-docs](https://github.com/terraform-docs/terraform-docs)|Generate documents for Terraform modules|DevOps tool|
|[pug](https://github.com/leg100/pug)|TUI for terraform, terragrunt|DevOps tool|
|[kubeseal](https://github.com/bitnami-labs/sealed-secrets)|Encrypt secret on Kubernetes cluster|DevOps tool|
|[steampipe](https://github.com/turbot/steampipe)|SQL console for API queries|DevOps tool|
|[goose](https://github.com/pressly/goose)|Database migration tool|DevOps tool|
|[ktea](https://github.com/jonas-grgt/ktea)|TUI client for Kafka|DevOps tool|
|[process-compose](https://github.com/F1bonacc1/process-compose)|Scheduler and orchestrator to manage non-containerized applications|DevOps tool|-
|[restic](https://github.com/restic/restic)|Backup program|SysOps tool|
|[goaccess](https://github.com/allinurl/goaccess)|Real-time web log analyzer|SysOps tool|
|[hl](https://github.com/pamburus/hl)|Log viewer and processor that translates JSON or logfmt logs into a pretty human-readable format|SysOps tool|
|[otel-cli](https://github.com/equinix-labs/otel-cli)|CLI tool to send OpenTelemetry traces|SysOps tool|
|[infracost](https://github.com/infracost/infracost)|Estimate cost of cloud infra via Terraform|FinOps tool|
|[k6](https://github.com/grafana/k6)|Load testing tool|Testing tool|
|[venom](https://github.com/ovh/venom)|Integration testing tool|Testing tool|
|[oha](https://github.com/hatoo/oha)|HTTP load generator tool|Testing tool|
|[shmig](https://github.com/mbucc/shmig)|Database migration tool|DevOps tool|
|[kubectl](https://github.com/kubernetes/kubectl)|Interactive CLI tool with Kubernetes cluster|DevOps tool|
|[helm](https://github.com/helm/helm)|Kubernetes package manager|DevOps tool|
|[gcloud](https://cloud.google.com/sdk)|Libraries and tools for interacting with Google Cloud products and services|DevOps tool|
|[aws](https://github.com/aws/aws-cli)|Libraries and tools for interacting with Amazon Web Services products and services|DevOps tool|
|[az](https://github.com/Azure/azure-cli)|Libraries and tools for interacting with Microsoft Azure products and services|DevOps tool|
|[pint](https://github.com/cloudflare/pint)|Linter for Prometheus rules|Linter|

# AI tools

|[ollama](https://github.com/ollama/ollama)|Get up and running LLMs|AI Tool|
|[fabric](https://github.com/danielmiessler/fabric)|Framework for augmenting humans using AI|AI tool|
|[aichat](https://github.com/sigoden/aichat)|All-in-one LLM CLI tool|AI tool|

# Miscellaneous applications

|Tool|Purpose|Used in|
|----|-------|-------|
|[cht](https://cht.sh)|Access to community cheat sheet|Miscellaneous|
|color16, color256, colorful, truecolor|Test CLI color|Miscellaneous|
|[now](https://github.com/apankrat/now.sh)|Prints current date/time while waiting for an input and echoing it to the stdout|Miscellaneous|
|[screensaver](https://github.com/pipeseroni/pipes.sh)|Show screensaver on CLI with pipes|Miscellaneous|
|[qrify](https://github.com/alexanderepstein/Bash-Snippets)|Show QR of text|Miscellaneous|
|[tmpmail](https://github.com/sdushantha/tmpmail)|Create temp mail address and receive emails|Miscellaneous|
|[trans](https://github.com/soimort/translate-shell)|Translate|Miscellaneous|
|[xpanes](https://github.com/greymd/tmux-xpanes)|Terminal divider with tmux|Miscellaneous|
|[cava](https://github.com/karlstav/cava)|Audio visualizer|Multimedia tool|
|[git-quick-stats](https://github.com/arzzen/git-quick-stats)|Show statistics of Git repository|Miscellaneous|
|[playerctl](https://github.com/altdesktop/playerctl)|Control media players that implement the MPRIS|Multimedia tool|
|[pipewire](https://github.com/PipeWire/pipewire)|Audio and video devices framework|Multimedia tool|
|[pulsemixer](https://github.com/GeorgeFilipkin/pulsemixer)|Alternative CLI tool for pavucontrol|Multimedia tool|
|[bluez](https://github.com/bluez/bluez)|Bluetooth controller|Multimedia tool|
|[mpv](https://github.com/mpv-player/mpv)|Media player|Multimedia tool|
|[pandoc](https://github.com/jgm/pandoc)|Universal markup converter|Miscellaneous|
|[exiftool](https://github.com/exiftool/exiftool)|Meta information reader/writer for image|Multimedia tool|
|[ImageMagick](https://github.com/ImageMagick/ImageMagick)|Image manipulation tool|Multimedia tool|
|[hyperfine](https://github.com/sharkdp/hyperfine)|Benchmarking tool for CLI apps|Miscellaneous|
|[cointop](https://github.com/arduino/arduino-cli)|TUI to track coin stats|Miscellaneous|
|[tickrs](https://github.com/tarkah/tickrs)|TUI to track stock stats|Miscellaneous|
|[pastel](https://github.com/sharkdp/pastel)|Generate, manipulate, convert colors CLI tool|Miscellaneous|
|[cht](https://cht.sh)|Access to community cheat sheet||
|[tldr](https://github.com/dbrgn/tealdeer)|Cheatsheet CLI tool|Miscellaneous|
|[yt-dlp](https://github.com/yt-dlp/yt-dlp)|Download videos tool|Miscellaneous|
|[viu](https://github.com/atanunq/viu)|View image on CLI|Miscellaneous|
|[ncspot](https://github.com/hrkfdn/ncspot)|Spotify CLI client|Miscellaneous|
|[telegram-desktop](https://desktop.telegram.org/)|Telegram desktop client|Miscellaneous|
|[bluetui](https://github.com/pythops/bluetui)|TUI for managing bluetooth|Multimedia tool|
|[gtt](https://github.com/eeeXun/gtt)|TUI for Google Translate and other services|Miscellaneous|
|[pptx2md](https://github.com/ssine/pptx2md)|Convert PowerPoint presentations to Markdown|Miscellaneous|
|[in2csv](https://github.com/wireservice/csvkit)|Convert various data formats to CSV|Miscellaneous|
|[lz4json](https://github.com/andikleen/lz4json)|C decompress tool for mozilla lz4json format|Miscellaneous|
