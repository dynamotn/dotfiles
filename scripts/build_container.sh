#!/bin/bash
set -Eeou pipefail
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Install custom certs
[ "$INTERNAL_CERT" != "" ] && echo "$INTERNAL_CERT" | sudo tee /etc/ca-certificates/trust-source/anchors/ssl_decryption.crt
sudo update-ca-trust

# Choose mirror for VN
echo "Server = http://mirror.bizflycloud.vn/archlinux/\$repo/os/\$arch" | sudo tee /etc/pacman.d/mirrorlist

# Prerequisite
sudo pacman -Sy --noconfirm git openssh chezmoi age expect

# Setup
export GIT_SSH_COMMAND="ssh -oStrictHostKeyChecking=no"
"$SCRIPT_DIR"/setup.sh -z
ssh-keygen -t ed25519 -f ~/.ssh/key/public_ed25519 -P ""
chezmoi apply
