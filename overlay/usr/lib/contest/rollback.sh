#!/usr/bin/env bash

set -euo pipefail

. /usr/lib/contest/common.sh

LOG="/var/log/contest-rollback.log"
MOUNT_TMP="/mnt/contest-rollback-target"

_log() {
    local ts
    ts=$(date -u +%H:%M:%S)
    echo "[${ts}] $*" | tee -a "${LOG}"
}

_die() {
    _log "FATAL: $*"
    exit 1
}

cleanup_mount() {
    if mountpoint -q "${MOUNT_TMP}" 2>/dev/null; then
        umount "${MOUNT_TMP}" || true
    fi
}
trap cleanup_mount EXIT

mkdir -p "$(dirname "${LOG}")"
[ "$(id -u)" -eq 0 ] || _die "Must run as root"

CONTEST_DIR="$(cmdline_param contest_dir)"
CONTEST_DIR="$(normalize_contest_dir "${CONTEST_DIR:-/contest}")"
MARKER_FILE="/run/contest-media${CONTEST_DIR}/.contest-installed"
[ -f "${MARKER_FILE}" ] || _die "No portable install marker found"
read_install_marker "${MARKER_FILE}"

mount_opts="$(mount_opts_for_fstype "${MARKER_TARGET_FSTYPE}" rw)"
mkdir -p "${MOUNT_TMP}"
mount -t "${MARKER_TARGET_FSTYPE}" -o "${mount_opts}" "${MARKER_TARGET_DEV}" "${MOUNT_TMP}" || \
    _die "Cannot mount target read-write"

contest_root="${MOUNT_TMP}${CONTEST_DIR}"
current_dir="$(contest_current_dir "${contest_root}")"
previous_dir="$(contest_previous_dir "${contest_root}")"

[ -d "${previous_dir}" ] || _die "No previous runtime found to rollback"
[ -d "${current_dir}" ] || _die "Current runtime missing"

tmp_dir="${contest_root}/rollback-tmp"
rm -rf "${tmp_dir}"
mv "${current_dir}" "${tmp_dir}"
mv "${previous_dir}" "${current_dir}"
mv "${tmp_dir}" "${previous_dir}"
if [ -r "${current_dir}/VERSION" ]; then
    write_runtime_version "${contest_root}" "$(tr -d '\n' < "${current_dir}/VERSION")"
fi
link_runtime_files "${contest_root}"

_log "Rollback completed. Reboot recommended."
