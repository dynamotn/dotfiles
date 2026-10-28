# System tuning

What is tuned beyond the kernel config ([kernel.md](kernel.md)), where it
lives under `root/`, and how to check it took effect. Apply with
`scz diff <path>` then `scz apply <path>`.

## Network

| Setting | Where | Why |
|---------|-------|-----|
| BBR paced by `fq`, built in and default | `<code>.tuning.config.tmpl` (`DEFAULT_BBR`, `DEFAULT_FQ`) | every socket gets it from boot, not once sysctl loads a module |
| `default_qdisc=fq`, `tcp_congestion_control=bbr` | `etc/sysctl.d/99-network.conf.tmpl` | the same on dist kernels |
| 16M socket buffer limits | same | high bandwidth-delay paths; the core limits also bound UDP (Tailscale, WireGuard, QUIC) |
| `tcp_mtu_probing=1`, `tcp_slow_start_after_idle=0`, `tcp_fastopen=3` | same | PMTU blackholes behind VPNs, idle keep-alive connections |
| `tcp_timestamps=1` | same | `tcp_tw_reuse`, PAWS and BBR's RTT samples need them; the offset is random per connection |
| Wi-Fi power saving off on a desktop | `etc/NetworkManager/conf.d/wifi-powersave.conf.tmpl` | latency and jitter on mains power; needs `hasWifi` in the chezmoi data |

Check: `sysctl net.core.default_qdisc net.ipv4.tcp_congestion_control`.

## Disks

| Setting | Where | Why |
|---------|-------|-----|
| btrfs `noatime,compress=zstd:1`, no `autodefrag` | `etc/fstab.tmpl` | reads write no metadata; faster compression on NVMe; autodefrag rewrites extents and unshares them from snapshots |
| Dirty pages capped at 256M / 1G on a PC or laptop | `etc/sysctl.d/80-writeback.conf.tmpl` | a slow USB copy no longer stalls every writer |
| BFQ for spinning disks | `etc/udev/rules.d/60-ioschedulers.rules` | responsiveness during long copies; NVMe keeps `none` |
| Journal capped at 200M (50M in RAM) on systemd | `etc/systemd/journald.conf.d/size.conf` | the default takes up to 4G of a small VM disk |

Check: `findmnt -t btrfs -o TARGET,OPTIONS`, `cat /sys/block/*/queue/scheduler`.

## Memory

- zswap with zstd, on by default (kernel config), its pool raised to a
  quarter of RAM with `zswap.max_pool_percent=25` in `etc/default/grub.tmpl`.
  zswap is built in, so the parameter can only go on the command line.
- MGLRU on, transparent huge pages on `madvise` only (kernel config).
- earlyoom kills one process at 10% free RAM and swap, before zram thrashing
  freezes the desktop. It prefers `shellcheck`, `shfmt` and `hunk`, the
  processes that piled up in past freezes, and avoids the compositor,
  terminal and session daemons. The arguments live once in
  `.chezmoitemplates/earlyoom/args.tmpl` and render to
  `etc/default/earlyoom.tmpl` on systemd and `etc/conf.d/earlyoom.tmpl` on
  OpenRC, each quoted the way that init system reads it
  (`scripts/test/earlyoom_config.bats` checks both get the same argv).
  dytoy installs and enables the service (`dytoy/earlyoom.yaml.tmpl`).
  After `scz apply`, restart it: `systemctl restart earlyoom` or
  `rc-service earlyoom restart`.

Check: `grep -r . /sys/module/zswap/parameters/`,
`journalctl -u earlyoom` or `/var/log/messages` for its kills.

## CPU scheduling

- Full preemption at 1000 Hz, tickless when idle, `SCHED_CACHE` keeping a
  process on one of the two CCD L3 caches (kernel config).
- A sched_ext scheduler, `scx_cosmos`, started on boot by `scx_loader`
  (`etc/scx_loader/config.toml.tmpl`, `etc/conf.d/scx_loader.tmpl` for its
  dbus dependency). When it runs it replaces the built-in scheduler for normal
  tasks; if it stalls, the kernel falls back on its own.
- `net.core.bpf_jit_harden=1` (`etc/sysctl.d/99-hardened.conf.tmpl`): with
  unprivileged BPF disabled, 2 would only slow root programs such as the
  scheduler.

Check: `cat /sys/kernel/sched_ext/state /sys/kernel/sched_ext/root/ops`;
switch live with `scxctl switch -s lavd`.

## Boot

- OpenRC starts independent services in parallel
  (`etc/rc.conf.d/parallel.conf`).
- Nothing waits for the network: `ntpd -g` replaces the one-shot
  `ntp-client`, and `netmount` is dropped since nothing is mounted over the
  network (dytoy `ntp.yaml`; on an installed machine run the `rc-update del`
  lines of its hook once).

## Portage builds

- Parallel emerges are capped by RAM, one per 4G, instead of by threads
  (`etc/portage/make.conf.tmpl`). Small packages keep one job per thread.
- Large C++ and Rust packages listed in `etc/portage/package.env/heavy` get
  one job per 2G of RAM (`etc/portage/env/heavy.conf.tmpl`).
- On the home PC, builds run in a tmpfs on `/var/tmp/portage` of half the
  RAM (`etc/fstab.tmpl`); the heavy packages build on disk in
  `/var/tmp/notmpfs`, as their trees outgrow it. After `scz apply`, run
  `mount /var/tmp/portage` once.
- Both read threads and RAM from `.chezmoitemplates/system/resources.yaml.tmpl`
  when rendered, so another machine scales on its own.

## Firmware

`etc/portage/savedconfig/sys-kernel/linux-firmware.tmpl` lists only what this
hardware loads. The ebuild writes the installed list back as
`linux-firmware-<version>`, which would take precedence over it;
`.chezmoiremove` deletes that copy on every apply.

## Limits and packages

- Login sessions may open 65536 files, up to 524288
  (`etc/security/limits.conf`): watchers and language servers exhaust 1024.
  systemd services and user services get the same through
  `etc/systemd/{system,user}.conf.d/limits.conf`, as they skip PAM.
- 524288 inotify watches and 1048576 memory maps
  (`etc/sysctl.d/70-dev.conf`), for watchers, Electron apps and games.
- apt skips the `Translation-*` indexes and retries a failed download three
  times (`etc/apt/apt.conf.d/10tuning`).

Check: `ulimit -n` in a new login shell.

## Power and GPU

- The office laptop boots with `amd_pstate=active` (`etc/default/grub.tmpl`),
  so its CPU follows the EPP hints of `etc/tlp.conf.tmpl`.
- With an NVIDIA GPU, the driver saves all video memory to `/var/tmp` across
  suspend and hibernate (`etc/modprobe.d/nvidia-pm.conf.tmpl`); the elogind
  sleep hook of nvidia-drivers switches it.

Check: `cat /sys/devices/system/cpu/amd_pstate/status` reads `active`;
`grep PreserveVideo /proc/driver/nvidia/params`, then suspend once.

## macOS

- Fast key repeat, no accent popup on a held key (`.macos/global.yaml.tmpl`).
- No `.DS_Store` on network or USB volumes
  (`.macos/com.apple.desktopservices.yaml`).
- `git status` uses the built-in fsmonitor daemon (`git/config.tmpl`).

## Termux

Android has no system layer here: `root/` is never applied, so only the
Termux app itself is tuned, in `home/dot_termux/termux.properties.tmpl`.

- No bell vibration, URLs open on tap, app UI follows `darkMode`.
- Catppuccin colors land in `~/.termux/colors.properties`, the only path the
  app reads them from; the font in `~/.termux/font.ttf`.
- `05-reload-termux` runs `termux-reload-settings` when either changes.

Check: open the drawer and compare its theme; `echo -e '\a'` stays silent.
