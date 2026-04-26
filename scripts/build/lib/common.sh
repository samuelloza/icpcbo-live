#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()   { echo -e "${GREEN}[contest-iso]${NC} $*"; }
warn()  { echo -e "${RED}[contest-iso WARN]${NC} $*" >&2; }
die()   { echo -e "${RED}[contest-iso FATAL]${NC} $*" >&2; exit 1; }
phase() { echo -e "\n${CYAN}${BOLD}==== $* ====${NC}\n"; }

require_cmd() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "Missing command: ${cmd}"
    done
}

mount_chroot() {
    mount --bind /dev "${ROOTFS_DIR}/dev"
    mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts"
    mount -t proc proc "${ROOTFS_DIR}/proc"
    mount -t sysfs sys "${ROOTFS_DIR}/sys"
    mount -t tmpfs tmpfs "${ROOTFS_DIR}/run"

    local cache_host="${DOWNLOAD_CACHE_DIR:-/work/download-cache}"
    mkdir -p "${cache_host}" "${ROOTFS_DIR}/work/download-cache"
    mount --bind "${cache_host}" "${ROOTFS_DIR}/work/download-cache"

    local apt_cache_host="${APT_CACHE_DIR:-/work/apt-cache}"
    mkdir -p "${apt_cache_host}" "${ROOTFS_DIR}/var/cache/apt/archives"
    mount --bind "${apt_cache_host}" "${ROOTFS_DIR}/var/cache/apt/archives"
}

umount_chroot() {
    local mp
    for mp in var/cache/apt/archives work/download-cache run sys proc dev/pts dev; do
        if mountpoint -q "${ROOTFS_DIR}/${mp}" 2>/dev/null; then
            umount -lf "${ROOTFS_DIR}/${mp}" || true
        fi
    done
}

latest_kernel_version() {
    ls -1 "${ROOTFS_DIR}"/boot/vmlinuz-* 2>/dev/null \
        | sed 's|.*/vmlinuz-||' \
        | sort -V \
        | tail -n1
}
