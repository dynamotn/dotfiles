# Kernel

`l30n4rd0d4v1nc1` runs a hand-configured `sys-kernel/gentoo-sources` kernel;
other Gentoo machines keep the `gentoo-kernel` dist kernel. Two files under
`/etc/kernel/gentoo-sources/` describe it:

| File            | Source                                              | Holds |
|-----------------|-----------------------------------------------------|-------|
| `base.config`   | `root/.chezmoitemplates/kernel/<code>.defconfig`    | hardware-trimmed defconfig |
| `tuning.config` | `root/etc/kernel/gentoo-sources/tuning.config.tmpl` | performance and security choices |

`scripts/kernel.sh` merges them into `/usr/src/linux/.config`, then stops if
Kconfig dropped any option of `tuning.config` (a missing dependency or a
renamed symbol), so a choice never disappears silently.

## Build and install

```bash
./scripts/kernel.sh --configure-only   # write and verify .config only
./scripts/kernel.sh                    # build, modules_install, @module-rebuild, install
```

The order matters: the NVIDIA modules are rebuilt before `make install`,
because installkernel runs dracut, which must find them for the initramfs.
Each new version gets its own `/boot` entry; the previous kernel stays in GRUB.

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

- A tuning choice goes in `tuning.config.tmpl`, with a comment saying why.
- A driver for new hardware goes in the base:
  `./scripts/kernel.sh --menuconfig --configure-only --save-base <repo>/root/.chezmoitemplates/kernel/<code>.defconfig`.

## SELinux

The kernel enables SELinux (`CONFIG_LSM` lists `selinux`); the policy is
`mcs` and the mode stays `permissive` in `/etc/selinux/config`.

1. Boot the new kernel and check `sestatus` reports `enabled`, `permissive`.
2. Relabel every filesystem: `rlpkg -a -r`, then reboot.
3. Review denials with `ausearch -m avc` (or `dmesg | grep avc`) and fix them.
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
