# Kernel

The machines listed in `gentooSourcesMachines`
(`home/.chezmoidata/kernel.yaml`, linked into the root source) run a
hand-configured `sys-kernel/gentoo-sources` kernel; every other Gentoo machine
keeps the `gentoo-kernel` dist kernel. That one list decides the kernel
package in world and dytoy, USE `dist-kernel` and the keyword pin. Two files
under `/etc/kernel/gentoo-sources/` describe each such kernel:

| File            | Source in `root/.chezmoitemplates/kernel/` | Holds |
|-----------------|--------------------------------------------|-------|
| `base.config`   | `<code>.defconfig`                         | hardware-trimmed defconfig |
| `tuning.config` | `<code>.tuning.config.tmpl`                | performance and security choices |

A new machine joins by adding its code to the list and both partials.
Tuning outside the kernel config (network, disks, memory, scheduler, boot,
portage builds) is described in [tuning.md](tuning.md).

`scripts/kernel.sh` merges them into `/usr/src/linux/.config`, then stops if
Kconfig dropped any option of `tuning.config` (a missing dependency or a
renamed symbol), so a choice never disappears silently.

## Build and install

```bash
./scripts/kernel.sh --configure-only   # write and verify .config only
./scripts/kernel.sh                    # build, modules_install, @module-rebuild, install
./scripts/kernel.sh --install-only     # resume: @module-rebuild and install, no build
```

`emerge` keeps the `--ask` of `EMERGE_DEFAULT_OPTS` when run from a terminal,
so its merge list and progress stay visible. If it ever hangs, interrupt it,
make sure no orphaned `emerge` is left (`pgrep -a emerge`), and resume with
`--install-only` rather than building again.

The NVIDIA modules are rebuilt before `make install`, so the kernel is never
in GRUB without a driver to go with it. Each new version gets its own `/boot`
entry; the previous kernel stays in GRUB.

## Initramfs

installkernel builds it with dracut, host-only (Gentoo's default). Root is on
NVMe and btrfs, both built in, so it holds little more than udev, btrfs tools
and the resume hook: about 15M. The NVIDIA modules stay out of it, as
nvidia-drivers intends; pulled in, they and the GSP firmware a Pascal card
never uses make it about 175M. Check one with
`lsinitrd /boot/initramfs-<version>.img | head -30`: an `Early CPIO image`
section with `AuthenticAMD.bin` means the Zen 3 microcode is loaded early,
which needs `amd-ucode/microcode_amd_fam19h.bin` from linux-firmware.

## Switching from gentoo-kernel

1. Review, then apply the system files:
   `scz diff /etc/portage /etc/kernel /etc/selinux /etc/dracut.conf.d`, then
   the same paths with `scz apply`.
2. `emerge --ask --noreplace sys-kernel/gentoo-sources dev-util/pahole`.
   USE `symlink` points `/usr/src/linux` at the new tree.
3. `emerge --ask --changed-use --deep @world`, so nvidia-drivers drops USE
   `dist-kernel`.
4. `./scripts/kernel.sh`, reboot, choose the `-gentoo` entry.
5. Keep `gentoo-kernel` until the new kernel has booted well a few times;
   only then `emerge --depclean sys-kernel/gentoo-kernel virtual/dist-kernel`.

## Changing the configuration

- A tuning choice goes in `<code>.tuning.config.tmpl`, with a comment saying why.
- A driver for new hardware goes in the base:
  `./scripts/kernel.sh --menuconfig --configure-only --save-base <repo>/root/.chezmoitemplates/kernel/<code>.defconfig`.

## Moving to a new major version

`package.accept_keywords/sys-kernel/gentoo-sources` pins one series (now
7.2, still `~amd64`), so portage never jumps to the next one on its own.
Both config files are written against that series' Kconfig. To move on:

1. Unpack the new tree anywhere writable and list what it adds:
   `make listnewconfig` after copying the running config (`zcat
   /proc/config.gz > .config`). Read the help of anything that touches the
   scheduler, memory, security or this hardware, and put the choices in
   `<code>.tuning.config.tmpl`.
2. `./scripts/kernel.sh --configure-only --source <tree> --refresh-base
   <repo>/root/.chezmoitemplates/kernel/<code>.defconfig` re-resolves the
   base against the new Kconfig (renamed or now built-in options drop out,
   hardware choices stay) and verifies the fragment on top of it.
3. Build the tree and the NVIDIA modules against it before switching: the
   GTX 1060 is held on the 580 driver branch, whose support for a new kernel
   is only known by compiling it.
4. Move the pin in `package.accept_keywords` to the new series.

Keep the old series' kernel in GRUB until the new one has booted well; once
`emerge --depclean` drops its sources, its NVIDIA modules can no longer be
rebuilt.

## SELinux

The kernel enables SELinux (`CONFIG_LSM` lists `selinux`); the policy is
`mcs` and the mode stays `permissive` in `/etc/selinux/config`.

1. Boot the new kernel and check `sestatus` reports `enabled`, `permissive`.
2. Relabel every filesystem: `rlpkg -a -r`, then reboot. `rlpkg` cannot see
   the mount-point directories hidden under the btrfs subvolumes, and early
   boot touches them before the mounts exist (`unlabeled_t` on `var`). Label
   them through a bind mount of `/`:

   ```bash
   mkdir -p /mnt/rootfs && mount --bind / /mnt/rootfs
   setfiles -r /mnt/rootfs /etc/selinux/mcs/contexts/files/file_contexts \
     /mnt/rootfs/{var,home,boot,snapshot}
   umount /mnt/rootfs
   ```

3. Review denials and fix them. `auditd` (dytoy `audit.yaml`, rules in
   `/etc/audit/audit.rules`) keeps every one in `/var/log/audit/audit.log`
   with its syscall context: `ausearch -m avc,user_avc,selinux_err -ts boot`,
   then `audit2why` to sort them. Denials logged before auditd starts, and
   any while it is down, only reach the kernel log:
   `grep -hE 'avc: +denied' /var/log/dmesg /var/log/messages`. Label
   errors are fixed by relabelling; real policy gaps go into the local module
   `/etc/selinux/local/dotfiles.te`, built and loaded with:

   ```bash
   cd /etc/selinux/local
   make -f /usr/share/selinux/mcs/include/Makefile dotfiles.pp
   semodule -i dotfiles.pp
   ```
4. Only then set `SELINUX=enforcing`. If a boot ever fails because of it,
   add `enforcing=0` to the kernel command line in GRUB to recover.

## Why some options are what they are

- `MSDOS_PARTITION` stays on: `sda` and most USB sticks use MBR.
- The Gentoo KSPP bundle stays off: it forbids hibernation, forces a strict
  IOMMU and panics on any oops. Cheap hardening (KASLR, IBT, shadow stack,
  FORTIFY, usercopy and freelist hardening, zeroed allocations, every CPU
  mitigation) and SELinux remain.
- `nouveau` is built as a module but blacklisted: it is what selects the DRM
  KMS and TTM helpers the proprietary driver needs.
- Hibernation is built in for `resume=`; with NVIDIA it also needs the
  driver's suspend hooks, which OpenRC does not run on its own.
