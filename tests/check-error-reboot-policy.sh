#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INITRAMFS_LOCAL="${PROJECT_DIR}/overlay/etc/initramfs-tools/scripts/local"
DEPLOY_SCRIPT="${PROJECT_DIR}/overlay/usr/lib/contest/deploy.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

grep -q '^stop_for_debug()' "${INITRAMFS_LOCAL}" \
    || fail "initramfs must provide a non-rebooting debug stop"

grep -q 'stop_for_debug "RAM insuficiente:' "${INITRAMFS_LOCAL}" \
    || fail "low-memory errors must stop for debugging"

grep -q 'stop_for_debug "Error de instalacion persistente:' "${INITRAMFS_LOCAL}" \
    || fail "installation errors must stop for debugging"

if grep -Eq 'force_reboot "(low-ram|install-error)"' "${INITRAMFS_LOCAL}"; then
    fail "fatal initramfs errors must not force a reboot"
fi

if grep -Eq '^[[:space:]]*(systemctl[[:space:]]+)?reboot([[:space:]]|$)' "${DEPLOY_SCRIPT}"; then
    fail "deploy errors must not reboot the machine"
fi

echo "PASS: fatal boot and deployment errors remain visible without rebooting."
