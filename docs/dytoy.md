# List of tools

<!-- toc -->

- [Prerequisite](#prerequisite)
- [System core tools](#system-core-tools)
- [Everyday terminal applications](#everyday-terminal-applications)
- [Cross platform GUI applications](#cross-platform-gui-applications)
- [Wayland server applications](#wayland-server-applications)
- [MacOS GUI applications](#macos-gui-applications)
- [Network tools](#network-tools)
- [Security tools](#security-tools)
- [Development tools](#development-tools)
- [DevOps tools](#devops-tools)
- [AI tools](#ai-tools)
- [Android tools](#android-tools)
- [Miscellaneous applications](#miscellaneous-applications)

<!-- tocstop -->

## Prerequisite

|Tool|Purpose|
|----|-------|
|[git](https://github.com/git/git)|Source version control system|
|[yq](https://github.com/mikefarah/yq)|YAML processor|
|[chezmoi](https://github.com/twpayne/chezmoi)|Manage dotfiles across machines|
|[age](https://github.com/FiloSottile/age)|Simple file encryption|
|`tar`, `unzip`, `gzip`, `bzip2`|Uncompress file|

## System core tools

|Tool|Purpose|
|----|-------|
|[kernel](https://github.com/torvalds/linux)|Linux kernel for OS|
|[cronie](https://github.com/cronie-crond/cronie)|Run scheduled tasks|
|`ntp`|NTP client to sync system clock|
|[auto-cpufreq](https://github.com/AdnanHodzic/auto-cpufreq)|Automatic CPU speed & power optimizer|
|[grub](https://www.gnu.org/software/grub/)|Bootloader for system|
|[flatpak](https://github.com/flatpak/flatpak)|Linux application sandboxing and distribution framework|

## Everyday terminal applications

|Tool|Purpose|
|----|-------|
|[neovim](https://github.com/neovim/neovim)|My love editor, and IDE in my eyes|
|[rbw](https://github.com/dynamotn/rbw)|Bitwarden CLI tool|
|[fish](https://github.com/fish-shell/fish-shell)|Smart command line shell|
|[tmux](https://github.com/tmux/tmux)|Terminal multiplexer|
|[zellij](https://github.com/zellij-org/zellij)|Terminal multiplexer|
|[grc](https://github.com/garabik/grc)|Colorise for some GNU/Linux commands|
|[tree-sitter](https://github.com/tree-sitter/tree-sitter)|Parser generator tool for syntax|
|[w3m](https://github.com/acg/w3m)|Text-based web browser|
|[git-lfs](https://github.com/git-lfs/git-lfs)|Git extension for large files|
|[jq](https://github.com/stedolan/jq)|JSON processor|
|[delta](https://github.com/dandavison/delta)|Syntax highlighting pager for git, diff, and grep output|
|[bat](https://github.com/sharkdp/bat)|Alternative to `cat` with syntax highlighting and Git integration|
|[ov](https://github.com/noborus/ov)|Alternative to `less`, `more`, `tail -f`|
|[tspin](https://github.com/bensadeh/tailspin)|Alternative to `tail` with highlighter|
|[fd](https://github.com/sharkdp/fd)|Alternative to `find`, simpler and faster|
|[eza](https://github.com/eza-community/eza)|Alternative to `ls` with colours, faster|
|[ripgrep](https://github.com/BurntSushi/ripgrep)|Alternative to `grep`, with Git integration and faster|
|[gping](https://github.com/orf/gping)|Alternative to `ping` with graph|
|[wtf](https://github.com/wtfutil/wtf)|Personal information dashboard on CLI|
|[zoxide](https://github.com/ajeetdsouza/zoxide)|Alternative to `cd` with smarter|
|[mise](https://github.com/jdx/mise)|All-in-one version manager|
|[vivid](https://github.com/sharkdp/vivid)|A themeable LS_COLORS generator with database|
|[navi](https://github.com/denisidoro/navi)|Cheatsheet CLI tool|
|[btop](https://github.com/aristocratos/btop)|Alternative to `htop` and `glances`|
|[himalaya](https://github.com/soywod/himalaya)|Email CLI tool|
|[smug](https://github.com/ivaaaan/smug)|Tmux session manager|
|[projekt](https://github.com/dynamotn/projekt)|Smart CLI command to manage project folder|
|[pomodoro](https://github.com/open-pomodoro/openpomodoro-cli)|CLI command for Pomodoro tracker|
|[procs](https://github.com/dalance/procs)|Alternative to `ps` with colours, tree view...|
|[rclone](https://github.com/rclone/rclone)|Sync files to and from cloud providers|
|[viddy](https://github.com/sachaos/viddy)|Alternative to `watch` with colours, diff, time machine...|
|[dust](https://github.com/bootandy/dust)|Alternative to `du` with more intuitive|
|[duf](https://github.com/muesli/duf)|Alternative to `df` with colours...|
|[pulsemixer](https://github.com/GeorgeFilipkin/pulsemixer)|Alternative CLI tool for pavucontrol|
|[wol](https://github.com/sabhiram/go-wol)|Wake-on-LAN utility|
|[fzf](https://github.com/junegunn/fzf)|Fuzzy finder on CLI|
|[lazygit](https://github.com/jesseduffield/lazygit)|TUI for git|
|[yazi](https://github.com/sxyazi/yazi)|TUI file manager|
|[jira](https://github.com/ankitpokhrel/jira-cli)|Interactive CLI tool with JIRA|
|[glab](https://gitlab.com/gitlab-org/cli)|Interactive CLI tool with Gitlab|
|[gh](https://github.com/cli/cli)|Interactive CLI tool with Github|

## Cross platform GUI applications

|Tool|Purpose|
|----|-------|
|[kitty](https://github.com/kovidgoyal/kitty)|Terminal emulator, support ligature fonts and GPU|
|[firefox](https://www.mozilla.org/en-US/firefox/)|Web browser|
|[zen-browser](https://zen-browser.app/)|Web browser with modern features|
|[thunderbird](https://www.thunderbird.net/)|Email client|
|[nvtop](https://github.com/Syllo/nvtop)|Monitor resources of GPU|
|[obsidian](https://obsidian.md/)|Note-taking app|
|[steam](https://store.steampowered.com/about/)|Online game platform|

## Wayland server applications

|Tool|Purpose|
|----|-------|
|[xdg-user-dirs](https://www.freedesktop.org/wiki/Software/xdg-user-dirs/)|Manage well-known user directories|
|[hyprland](https://github.com/hyprwm/Hyprland)|Window manager for Wayland|
|[hyprshade](https://github.com/loqusion/hyprshade)|Adjusts the color temperature of screen|
|[hdrop](https://github.com/hyprwm/contrib#hdrop)|Dropdown utilities|
|[eww](https://github.com/elkowar/eww)|Widgets and status bar|
|[wofi](https://sr.ht/~scoopta/wofi/)|Application launcher, simple switcher|
|[wtype](https://github.com/atx/wtype)|Simulate keyboard input for Wayland|
|[swww](https://github.com/LGFae/swww)|Animated wallpaper daemon|
|[greetd](https://sr.ht/~kennylevinsen/greetd/)|GreetD, display manager for Wayland|
|[regreet](https://github.com/rharish101/ReGreet)|ReGreet, greeter for GreetD|
|[hyprlock](https://github.com/hyprwm/hyprlock)|Screen locker for Wayland|
|[swappy](https://github.com/jtheoof/swappy)|Editing snapshot tool for Wayland|
|[grim](https://github.com/emersion/grim)|Screen capturing tool for Wayland|
|[slurp](https://github.com/emersion/slurp)|Selecting region tool for Wayland|
|[swaync](https://github.com/ErikReider/SwayNotificationCenter)|Notification center for Wayland|
|[cliphist](https://github.com/sentriz/cliphist)|Clipboard manager for Wayland|
|[shikane](https://github.com/hw0lff/shikane)|Automatically detects and configures connected monitors|
|[wdisplays](https://github.com/cyclopsian/wdisplays)|Configure display monitors manually with GUI|
|[ibus-bamboo](https://github.com/BambooEngine/ibus-bamboo)|Vietnamese input method for Ibus|
|[fcitx-bamboo](https://github.com/fcitx/fcitx5-bamboo)|Vietnamese input method for Fcitx|
|[libnotify](https://gitlab.gnome.org/GNOME/libnotify)|Library for sending desktop notifications to a notification daemon|

## MacOS GUI applications

|Tool|Purpose|
|----|-------|
|[sketchybar](https://github.com/FelixKratz/SketchyBar)|Status bar for MacOS|
|[aerospace](https://github.com/nikitabobko/AeroSpace)|Window manager for MacOS|
|[raycast](https://www.raycast.com/)|Launcher for everything|
|[alt-tab](https://github.com/lwouis/alt-tab-macos)|Windows alt-tab on macOS|

## Network tools

|Tool|Purpose|
|----|-------|
|`ssh`|SSH client|
|`netcat`|TCP/IP swiss army knife|
|[NetworkManager](https://networkmanager.dev/)|Linux network configuration tool suite|
|[tshark](https://www.wireshark.org/docs/man-pages/tshark.html)|CLI of Wireshark, network packet analysis|
|[bcc](https://github.com/iovisor/bcc)|Toolkit for IO analysis, networking, monitoring...|
|[trippy](https://github.com/fujiapple852/trippy)|CLI tool for network diagnostic|
|[termshark](https://github.com/gcla/termshark)|TUI to network packet analysis|
|[curlie](https://github.com/rs/curlie)|Alternative to `curl` with the ease of use from `httpie`|
|[bandwhich](https://github.com/imsnif/bandwhich)|CLI bandwidth utilization tool|
|[q](https://github.com/natesales/q)|Alternative to `dig`|
|[speedtest](https://github.com/showwin/speedtest-go)|CLI to test Internet speed|
|[websocat](https://github.com/vi/websocat)|Netcat, curl and socat for websocket|
|[flarectl](https://github.com/cloudflare/cloudflare-go)|Interactive CLI with Cloudflare|
|[oryx](https://github.com/pythops/oryx)|TUI for sniffing network traffic using eBPF|
|[httptap](https://github.com/monasticacademy/httptap)|CLI to view HTTP requests per command|
|[chisel](https://github.com/jpillora/chisel)|CLI to create TCP/UDP tunnel over HTTP|
|[vmware-horizon-client](https://www.omnissa.com/)|Virtual machine client to remote|
|[rustdesk](https://github.com/rustdesk/rustdesk)|Self-hosted remote desktop|
|[teleport](https://github.com/gravitational/teleport)|Identity-aware access proxy|

## Security tools

|Tool|Purpose|
|----|-------|
|`nftables`|Netfilter framework|
|[pam-u2f](https://github.com/Yubico/pam-u2f)|PAM U2F module|
|[wireguard](https://www.wireguard.com/)|Simple and modern VPN|
|[tailscale](https://github.com/tailscale/tailscale)|VPN built on Wireguard to connect securely to my machines|
|[fail2ban](https://github.com/fail2ban/fail2ban)|Intrusion prevention software framework|
|[radare2](https://github.com/radareorg/radare2)|Reverse engineering framework|
|[lynis](https://github.com/CISOfy/lynis)|Security auditing and hardening tool|
|[anti-ddos](https://github.com/anti-ddos/Anti-DDOS)|Anti DDOS|
|[kubescape](https://github.com/kubescape/kubescape)|Kubernetes security platform|
|[checkov](https://github.com/bridgecrewio/checkov)|IaC security analyzer|
|[trivy](https://github.com/aquasecurity/trivy)|Security scanner|
|[amass](https://github.com/owasp-amass/amass)|Network mapping of attack surfaces and external asset discovery|
|[osintui](https://github.com/wssheldon/osintui)|Open source intelligence tool|
|[tsui](https://github.com/neuralinkcorp/tsui)|TUI for Tailscale|
|[haiti](https://github.com/noraj/haiti)|Hash type identifier|
|[anti-ddos](https://github.com/anti-ddos/Anti-DDOS)|Anti DDOS|
|[gitleaks](https://github.com/gitleaks/gitleaks)|Detect secrets in git repos|
|[binsider](https://github.com/orhun/binsider)|Reverse engineering tool to analyze ELF binaries|

## Development tools

|Tool|Purpose|
|----|-------|
|[shdoc](https://github.com/reconquest/shdoc)|Generate documents for Bash shell scripts|
|[watchexec](https://github.com/watchexec/watchexec)|Detects modifications and run command|
|[gomplate](https://github.com/hairyhenderson/gomplate)|Template rendering, like jinja|
|[semantic-release](https://github.com/go-semantic-release/semantic-release)|Semantic release|
|[svu](https://github.com/caarlos0/svu)|Get Semantic version|
|[hugo](https://github.com/gohugoio/hugo)|Build static website|
|[trdsql](https://github.com/noborus/trdsql)|CLI execute SQL queries tool|
|[step](https://github.com/smallstep/cli)|CLI tool for PKI systems and workflows|
|[stripe](https://github.com/stripe/stripe-cli)|CLI to build, test Stripe integration|
|[d2](https://github.com/terrastruct/d2)|Diagram as code tool|
|[d2plugin-tala](https://github.com/terrastruct/TALA)|Engine plugin TALA for d2|
|[zrok](https://github.com/openziti/zrok)|Peer-to-peer sharing platform|
|[arduino](https://github.com/arduino/arduino-cli)|CLI to manage Arduino board|
|[posting](https://github.com/darrenburns/posting)|Powerful HTTP client with TUI same as Postman|
|[euporie](https://github.com/joouha/euporie)|Jupyter notebooks in CLI|
|[rust](https://github.com/rust-lang/rust)|Compiler and library for Rust|
|[go](https://github.com/golang/go)|Compiler and library for Go|
|[nodejs](https://github.com/nodejs/node)|JavaScript runtime|
|[deno](https://github.com/denoland/deno)|JavaScript runtime|
|[uv](https://github.com/astral-sh/uv)|Modern Python package and project manager|
|[prek](https://github.com/j178/pre-commit)|Framework for manage pre-commit hooks, re-engineered in Rust|
|[mkcert](https://github.com/FiloSottile/mkcert)|Make locally-trusted development certificates|
|[scc](github.com/boyter/scc)|Display statistics about code|

## DevOps tools

|Tool|Purpose|
|----|-------|
|[docker](https://docs.docker.com/engine/)|Manage containers|
|[lima](https://github.com/lima-vm/lima)|Linux VM on MacOS|
|[docker-compose](https://github.com/docker/compose)|Run multi-container applications|
|[docker-buildx](https://github.com/docker/buildx)|Extended build capabilities for Docker|
|[lazydocker](https://github.com/jesseduffield/lazydocker)|Interactive TUI with Docker and Compose|
|[dive](https://github.com/wagoodman/dive)|Explore each layer in Docker images|
|[diffoci](https://github.com/reproducible-containers/diffoci)|Diff Docker and OCI container images|
|[skopeo](https://github.com/containers/skopeo)|CLI tool for various operations with remote image repositories|
|[k9s](https://github.com/derailed/k9s)|Interactive TUI with Kubernetes cluster|
|[krew](https://github.com/kubernetes-sigs/krew)|Plugin manager for kubectl|
|[k0sctl](https://github.com/k0sproject/k0sctl)|Bootstrap and manage k0s cluster|
|[talosctl](https://github.com/siderolabs/talos)|Bootstrap and manage Talos Linux cluster|
|[helm-docs](https://github.com/norwoodj/helm-docs)|Generate documents for Helm chart|
|[kubeconform](https://github.com/yannh/kubeconform)|Validate Kubernetes manifest|
|[gonzo](https://github.com/control-theory/gonzo)|Log analysis TUI|
|[sops](https://github.com/getsops/sops)|Managing secrets in Git repositories|
|[argocd](https://github.com/argoproj/argo-cd)|Interactive with ArgoCD|
|[argonaut](https://github.com/darksworm/argonaut)|Interactive TUI with ArgoCD|
|[flux](https://github.com/fluxcd/flux2)|Interactive with Flux CD|
|[fly](https://github.com/superfly/flyctl)|CLI tool for cloud application on fly.io with container|
|[terraform](https://github.com/hashicorp/terraform)|IaC tool for building, changing, and versioning infrastructure|
|[opentofu](https://github.com/opentofu/opentofu)|IaC tool for building, changing, and versioning infrastructure (OSS fork from Terraform)|
|[terragrunt](https://github.com/gruntwork-io/terragrunt)|Wrapper for Terraform to provide extra tool|
|[terraformer](https://github.com/GoogleCloudPlatform/terraformer)|Generate Terraform from existing infrastructure|
|[terraform-docs](https://github.com/terraform-docs/terraform-docs)|Generate documents for Terraform modules|
|[pug](https://github.com/leg100/pug)|TUI for terraform, terragrunt|
|[kubeseal](https://github.com/bitnami-labs/sealed-secrets)|Encrypt secret on Kubernetes cluster|
|[steampipe](https://github.com/turbot/steampipe)|SQL console for API queries|
|[goose](https://github.com/pressly/goose)|Database migration tool|
|[dolphie](https://github.com/charles-001/dolphie)|Realtime analytics tool for MySQL/MariaDB, ProxySQL|
|[ktea](https://github.com/jonas-grgt/ktea)|TUI client for Kafka|
|[process-compose](https://github.com/F1bonacc1/process-compose)|Scheduler and orchestrator to manage non-containerized applications|
|[restic](https://github.com/restic/restic)|Backup program|
|[goaccess](https://github.com/allinurl/goaccess)|Real-time web log analyzer|
|[hl](https://github.com/pamburus/hl)|Log viewer and processor that translates JSON or logfmt logs into a pretty human-readable format|
|[otel-cli](https://github.com/equinix-labs/otel-cli)|CLI tool to send OpenTelemetry traces|
|[infracost](https://github.com/infracost/infracost)|Estimate cost of cloud infra via Terraform|
|[k6](https://github.com/grafana/k6)|Load testing tool|
|[venom](https://github.com/ovh/venom)|Integration testing tool|
|[updo](https://github.com/Owloops/updo)|Uptime monitoring CLI tool|
|[oha](https://github.com/hatoo/oha)|HTTP load generator tool|
|[kubectl](https://github.com/kubernetes/kubectl)|Interactive CLI tool with Kubernetes cluster|
|[helm](https://github.com/helm/helm)|Kubernetes package manager|
|[gcloud](https://cloud.google.com/sdk)|Libraries and tools for interacting with Google Cloud products and services|
|[aws](https://github.com/aws/aws-cli)|Libraries and tools for interacting with Amazon Web Services products and services|
|[az](https://github.com/Azure/azure-cli)|Libraries and tools for interacting with Microsoft Azure products and services|
|[pint](https://github.com/cloudflare/pint)|Linter for Prometheus rules|

## AI tools

|Tool|Purpose|
|----|-------|
|[ollama](https://github.com/ollama/ollama)|Get up and running LLMs|
|[fabric](https://github.com/danielmiessler/fabric)|Framework for augmenting humans using AI|
|[aichat](https://github.com/sigoden/aichat)|All-in-one LLM CLI tool|
|[claude](https://github.com/anthropics/claude-code)|CLI tool for Anthropic's Claude LLM|
|[copilot](https://github.com/github/copilot-cli)|CLI tool for GitHub Copilot|
|[gemini](https://github.com/google-gemini/gemini-cli)|CLI tool for Google Gemini LLM|

## Android tools
|Tool|Purpose|
|----|-------|
|[termux](https://github.com/termux/termux-app)|Terminal emulator for Android|
|[waydroid](https://github.com/waydroid/waydroid)|Android environment on Linux with container-based approach|
|[bluestacks](https://www.bluestacks.com/)|Android environment on MacOS|
|[android-tools](developer.android.com/tools/releases/platform-tools)|Android development tools|
|[fdroidcl](https://github.com/Hoverth/fdroidcl)|CLI for F-Droid|
|[immich](https://github.com/immich-app/immich)|Client for self-hosted photo, video server|

## Miscellaneous applications

|Tool|Purpose|
|----|-------|
|[cht](https://cht.sh)|Access to community cheat sheet|
|color16, color256, colorful, truecolor|Test CLI color|
|[now](https://github.com/apankrat/now.sh)|Prints current date/time while waiting for an input and echoing it to the stdout|
|[screensaver](https://github.com/pipeseroni/pipes.sh)|Show screensaver on CLI with pipes|
|[qrify](https://github.com/alexanderepstein/Bash-Snippets)|Show QR of text|
|[tmpmail](https://github.com/sdushantha/tmpmail)|Create temp mail address and receive emails|
|[trans](https://github.com/soimort/translate-shell)|Translate|
|[xpanes](https://github.com/greymd/tmux-xpanes)|Terminal divider with tmux|
|[cava](https://github.com/karlstav/cava)|Audio visualizer|
|[git-quick-stats](https://github.com/arzzen/git-quick-stats)|Show statistics of Git repository|
|[playerctl](https://github.com/altdesktop/playerctl)|Control media players that implement the MPRIS|
|[pipewire](https://github.com/PipeWire/pipewire)|Audio and video devices framework|
|[pulsemixer](https://github.com/GeorgeFilipkin/pulsemixer)|Alternative CLI tool for pavucontrol|
|[bluez](https://github.com/bluez/bluez)|Bluetooth controller|
|[mpv](https://github.com/mpv-player/mpv)|Media player|
|[pandoc](https://github.com/jgm/pandoc)|Universal markup converter|
|[exiftool](https://github.com/exiftool/exiftool)|Meta information reader/writer for image|
|[ImageMagick](https://github.com/ImageMagick/ImageMagick)|Image manipulation tool|
|[hyperfine](https://github.com/sharkdp/hyperfine)|Benchmarking tool for CLI apps|
|[cointop](https://github.com/cointop-sh/cointop)|TUI to track coin stats|
|[tickrs](https://github.com/tarkah/tickrs)|TUI to track stock stats|
|[matcha](https://github.com/piqoni/matcha)|Daily digest generator for RSS feeds and Google News with LLM|
|[pastel](https://github.com/sharkdp/pastel)|Generate, manipulate, convert colors CLI tool|
|[cht](https://cht.sh)|Access to community cheat sheet|
|[tldr](https://github.com/dbrgn/tealdeer)|Cheatsheet CLI tool|
|[yt-dlp](https://github.com/yt-dlp/yt-dlp)|Download videos tool|
|[viu](https://github.com/atanunq/viu)|View image on CLI|
|[ncspot](https://github.com/hrkfdn/ncspot)|Spotify CLI client|
|[rmpc](https://github.com/mierak/rmpc)|TUI client for Music Player Daemon, with Youtube support|
|[telegram-desktop](https://desktop.telegram.org/)|Telegram desktop client|
|[bluetui](https://github.com/pythops/bluetui)|TUI for managing bluetooth|
|[gtt](https://github.com/eeeXun/gtt)|TUI for Google Translate and other services|
|[pptx2md](https://github.com/ssine/pptx2md)|Convert PowerPoint presentations to Markdown|
|[in2csv](https://github.com/wireservice/csvkit)|Convert various data formats to CSV|
|[lz4json](https://github.com/andikleen/lz4json)|C decompress tool for mozilla lz4json format|
|[xleak](https://github.com/bgreenwell/xleak)|TUI for view Excel files|
