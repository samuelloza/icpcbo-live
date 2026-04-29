#!/usr/bin/env bash

set -euo pipefail

NOW="$(date --utc +%Y-%m-%dT%H:%M:%SZ)"
SINCE="10 minutes ago"

mkdir -p /var/lib/statsbo

if [[ -f /var/lib/statsbo/last_log_time ]]; then
    SINCE="$(cat /var/lib/statsbo/last_log_time)"
fi

BOOT_LOGS_FILE="$(mktemp)"
SYS_LOGS_FILE="$(mktemp)"
KERNEL_LOGS_FILE="$(mktemp)"

cleanup() {
    rm -f "${BOOT_LOGS_FILE}" "${SYS_LOGS_FILE}" "${KERNEL_LOGS_FILE}"
}
trap cleanup EXIT

journalctl -p err --since "${SINCE}" --no-pager > "${SYS_LOGS_FILE}" 2>/dev/null || true
journalctl -k -p err --since "${SINCE}" --no-pager > "${KERNEL_LOGS_FILE}" 2>/dev/null || true

if [[ ! -f /var/lib/statsbo/boot_sent ]]; then
    journalctl -b --no-pager > "${BOOT_LOGS_FILE}" 2>/dev/null || true
    touch /var/lib/statsbo/boot_sent
fi

printf '%s\n' "${NOW}" > /var/lib/statsbo/last_log_time

/usr/local/bin/stats-build-logs.py \
    "${NOW}" \
    "${BOOT_LOGS_FILE}" \
    "${SYS_LOGS_FILE}" \
    "${KERNEL_LOGS_FILE}"
