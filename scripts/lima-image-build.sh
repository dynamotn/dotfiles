#!/usr/bin/env bash
# @file lima-image-build.sh
# @brief Build an Arch Linux ARM aarch64 cloud image for Lima
# @description Runs as root inside a Debian/Ubuntu builder VM, which
#   `lima-image.sh` starts on the host. It pacstraps a fresh system from the
#   Arch Linux ARM repos into a raw disk, makes it boot with systemd-boot and
#   cloud-init the way Lima expects, and writes a compressed qcow2.
SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/dybatpho/init.sh
. "${SCRIPT_DIR}/lib/dybatpho/init.sh" --modules cli
dybatpho::register_common_handlers

ALARM_MIRROR="http://mirror.archlinuxarm.org/\$arch/\$repo"
ALARM_KEYRING_URL="https://raw.githubusercontent.com/archlinuxarm/PKGBUILDs/master/core/archlinuxarm-keyring"
WORK_DIR="/var/tmp/alarm-build"
MNT="${WORK_DIR}/root"
LOOP=""

# Lima needs sudo and sshfs in the guest and installs rsync on every boot;
# shipping them avoids a partial upgrade on first boot.
PACKAGES=(
  base linux-aarch64 archlinuxarm-keyring
  sudo openssh rsync sshfs
  cloud-init cloud-guest-utils gptfdisk
)

#######################################
# @description Spec of lima-image-build.sh
# @noargs
#######################################
function _spec_main {
  dybatpho::opts::setup "Build an Arch Linux ARM cloud image" MAIN_ARGS action:"_main"
  dybatpho::opts::param "Directory that receives the qcow2" OUTPUT_DIR --output -o init:="/output"
  dybatpho::opts::param "Image size in GiB" IMAGE_SIZE --size -s init:="3"
  dybatpho::opts::param "Log level" LOG_LEVEL --log-level -l init:="info" \
    validate:"dybatpho::validate_log_level \$OPTARG"
  dybatpho::opts::disp "Show help" --help -h action:"dybatpho::generate_help _spec_main"
}

#######################################
# @description Unmount the target and detach the loop device, so a failed
#   build does not leave the builder holding the raw disk
# @noargs
#######################################
function _cleanup {
  if [[ -d "${MNT}" ]] && mountpoint -q "${MNT}"; then
    umount -R "${MNT}" || umount -R -l "${MNT}" || true
  fi
  if [[ -n "${LOOP}" ]]; then
    losetup -d "${LOOP}" || true
  fi
}

#######################################
# @description Install the build tools and make the Debian pacman trust the
#   Arch Linux ARM keys
# @noargs
#######################################
function _prepare_host {
  local file
  dybatpho::header "Installing build tools"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends \
    arch-install-scripts pacman-package-manager makepkg \
    gdisk dosfstools e2fsprogs qemu-utils curl ca-certificates zstd xz-utils

  dybatpho::header "Trusting the Arch Linux ARM keyring"
  mkdir -p /usr/share/keyrings
  for file in archlinuxarm.gpg archlinuxarm-trusted archlinuxarm-revoked; do
    curl -fsSL --connect-timeout 10 --max-time 120 "${ALARM_KEYRING_URL}/${file}" -o "/usr/share/keyrings/${file}"
  done
  pacman-key --init
  pacman-key --populate archlinuxarm

  # A private config keeps the builder's own /etc/pacman.conf untouched
  mkdir -p "${WORK_DIR}"
  printf 'Server = %s\n' "${ALARM_MIRROR}" > "${WORK_DIR}/mirrorlist"
  cat > "${WORK_DIR}/pacman.conf" << EOF
[options]
Architecture = aarch64
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional
ParallelDownloads = 5

[core]
Include = ${WORK_DIR}/mirrorlist

[extra]
Include = ${WORK_DIR}/mirrorlist

[alarm]
Include = ${WORK_DIR}/mirrorlist
EOF
}

#######################################
# @description Create and mount the raw disk: an ESP on /boot, then root last
#   so cloud-init's growpart can extend it to the Lima disk size
# @arg $1 string Path of the raw image
#######################################
# dyshellint disable=SC2154 IMAGE_SIZE is assigned by dybatpho::opts from _spec_main
function _make_disk {
  local raw
  dybatpho::expect_args raw -- "$@"
  dybatpho::header "Partitioning ${IMAGE_SIZE}GiB disk"
  rm -f -- "${raw}"
  truncate -s "${IMAGE_SIZE}G" "${raw}"
  sgdisk --clear --align-end \
    --new 1:0:+512M --typecode=1:ef00 --change-name=1:ESP \
    --new 2:0:0 --typecode=2:8305 --change-name=2:root "${raw}"
  LOOP="$(losetup --find --partscan --show "${raw}")"
  udevadm settle
  mkfs.fat -F32 -n ESP "${LOOP}p1"
  mkfs.ext4 -q -L root "${LOOP}p2"
  mkdir -p "${MNT}"
  mount "${LOOP}p2" "${MNT}"
  mkdir -p "${MNT}/boot"
  mount "${LOOP}p1" "${MNT}/boot"
}

#######################################
# @description Install the system and configure boot, network and first boot
# @noargs
#######################################
function _install_system {
  local root_uuid
  dybatpho::header "Installing ${PACKAGES[*]}"
  # -G and -M: the target gets its own keyring (on first boot) and the
  # mirrorlist from its pacman-mirrorlist package, not the builder's
  pacstrap -C "${WORK_DIR}/pacman.conf" -G -M "${MNT}" "${PACKAGES[@]}"
  genfstab -U "${MNT}" >> "${MNT}/etc/fstab"
  root_uuid="$(blkid -s UUID -o value "${LOOP}p2")"

  dybatpho::header "Configuring the system"
  ln -sf /usr/share/zoneinfo/UTC "${MNT}/etc/localtime"
  printf 'LANG=C.UTF-8\n' > "${MNT}/etc/locale.conf"
  printf 'archlinux\n' > "${MNT}/etc/hostname"

  # vz exposes the serial port as virtio-console, so the log reaches
  # ~/.lima/<vm>/serialv.log only on hvc0
  mkdir -p "${MNT}/boot/loader/entries"
  printf 'default arch.conf\ntimeout 0\n' > "${MNT}/boot/loader/loader.conf"
  cat > "${MNT}/boot/loader/entries/arch.conf" << EOF
title   Arch Linux ARM
linux   /Image
initrd  /initramfs-linux.img
options root=UUID=${root_uuid} rw rootwait console=tty0 console=hvc0
EOF

  # Fallback only: cloud-init renders the real network from Lima's config
  cat > "${MNT}/etc/systemd/network/99-dhcp.network" << 'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes
DNSSEC=no
EOF

  # Each VM makes its own keyring instead of sharing the one baked in
  cat > "${MNT}/etc/systemd/system/pacman-init.service" << 'EOF'
[Unit]
Description=Initialize the pacman keyring
Before=sshd.service cloud-final.service
ConditionFirstBoot=yes

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/pacman-key --init
ExecStart=/usr/bin/pacman-key --populate archlinuxarm

[Install]
WantedBy=multi-user.target
EOF

  arch-chroot "${MNT}" /bin/bash -euo pipefail << 'EOF'
# --no-variables: never write the builder's own EFI NVRAM; vz boots the
# removable path EFI/BOOT/BOOTAA64.EFI
bootctl install --esp-path=/boot --no-variables
# Without autodetect the image keeps every module, not only the builder's
mkinitcpio -p linux-aarch64 -S autodetect
systemctl enable systemd-networkd systemd-resolved systemd-timesyncd sshd \
  cloud-init-main cloud-init-local cloud-init-network cloud-config \
  cloud-final pacman-init
EOF
  ln -sf /run/systemd/resolve/stub-resolv.conf "${MNT}/etc/resolv.conf"
}

#######################################
# @description Strip what must differ per VM, then shrink and convert
# @arg $1 string Path of the raw image
# @arg $2 string Path of the qcow2 to write
#######################################
function _finalize {
  local raw qcow2
  dybatpho::expect_args raw qcow2 -- "$@"
  dybatpho::header "Finalizing"
  rm -f -- "${MNT:?}/etc/machine-id"
  rm -rf -- "${MNT:?}/etc/pacman.d/gnupg"
  rm -rf -- "${MNT:?}/var/cache/pacman/pkg/"*
  fstrim "${MNT}/boot" || true
  fstrim "${MNT}" || true
  _cleanup
  LOOP=""

  dybatpho::header "Writing ${qcow2}"
  mkdir -p "$(dirname "${qcow2}")"
  qemu-img convert -c -f raw -O qcow2 "${raw}" "${qcow2}"
  rm -f -- "${raw}"
}

#######################################
# @description Main function
# @noargs
#######################################
# dyshellint disable=SC2154 OUTPUT_DIR and IMAGE_SIZE are assigned by dybatpho::opts from _spec_main
function _main {
  local name raw machine qcow2
  ((EUID == 0)) || dybatpho::die "Run as root inside the builder VM"
  machine="$(uname -m)"
  [[ "${machine}" == "aarch64" ]] || dybatpho::die "The builder must be aarch64"
  dybatpho::is file /etc/debian_version || dybatpho::die "The builder must be Debian or Ubuntu"

  name="Arch-Linux-aarch64-cloudimg-$(date -u '+%Y%m%d')"
  raw="${WORK_DIR}/${name}.img"
  dybatpho::trap _cleanup EXIT

  _prepare_host
  _make_disk "${raw}"
  _install_system
  qcow2="$(dybatpho::path_join "${OUTPUT_DIR}" "${name}.qcow2")"
  _finalize "${raw}" "${qcow2}"
  dybatpho::success "Built ${name}.qcow2"
}

dybatpho::generate_from_spec _spec_main "$@"
