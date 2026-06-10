#!/usr/bin/env bash

set -euo pipefail

for mod in overlay squashfs loop ext4 xfs vfat exfat ntfs3; do
    grep -qx "${mod}" /etc/initramfs-tools/modules || echo "${mod}" >> /etc/initramfs-tools/modules
done

if [[ -f /etc/initramfs-tools/scripts/local ]]; then
    chmod +x /etc/initramfs-tools/scripts/local
fi

if [[ -f /etc/initramfs-tools/hooks/contest-overlay-tools ]]; then
    chmod +x /etc/initramfs-tools/hooks/contest-overlay-tools
fi

update-initramfs -c -k all
