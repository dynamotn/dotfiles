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
| Dirty pages capped at 256M / 1G | `etc/sysctl.d/80-writeback.conf.tmpl` | a slow USB copy no longer stalls every writer |
| BFQ for spinning disks | `etc/udev/rules.d/60-ioschedulers.rules` | responsiveness during long copies; NVMe keeps `none` |

Check: `findmnt -t btrfs -o TARGET,OPTIONS`, `cat /sys/block/*/queue/scheduler`.

## Memory

- zswap with zstd, on by default (kernel config), its pool raised to a
  quarter of RAM with `zswap.max_pool_percent=25` in `etc/default/grub.tmpl`.
  zswap is built in, so the parameter can only go on the command line.
- MGLRU on, transparent huge pages on `madvise` only (kernel config).

Check: `grep -r . /sys/module/zswap/parameters/`.

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
- Both read threads and RAM from `.chezmoitemplates/system/resources.yaml.tmpl`
  when rendered, so another machine scales on its own.

## Firmware

`etc/portage/savedconfig/sys-kernel/linux-firmware.tmpl` lists only what this
hardware loads. The ebuild writes the installed list back as
`linux-firmware-<version>`, which would take precedence over it;
`.chezmoiremove` deletes that copy on every apply.
