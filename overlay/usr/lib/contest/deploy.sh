#!/usr/bin/env bash
# Deploys the contest runtime to a local disk partition.
#
# Called automatically by contest-deploy.service on the first ISO boot.
# Idempotent: exits immediately if already deployed (marker file present).
#
# GRUB lives on the ISO — this script only copies contest files.
# No bootloader installation is done here; the ISO's GRUB detects the
# marker file (.contest-installed) and shows the HDD boot entry automatically.
#
# Filesystem support:
#   ext4 / xfs  — overlay dirs created directly on the partition (native xattr)
#   ntfs / vfat / other — a fixed-size ext4 image (overlay.img) is created
#                         inside the contest folder and loop-mounted at boot
#
# Usage: deploy.sh [TARGET_DEVICE]
# Override via kernel cmdline: contest.deploy_target=/dev/sdXN

set -euo pipefail

. /usr/lib/contest/common.sh

[ -r /etc/contestiso/update.env ] && . /etc/contestiso/update.env

LOG="/var/log/contest-deploy.log"
MARKER=".contest-installed"
MIN_FREE_MB=5120
OVERLAY_IMG_SIZE_MB=4096   # 4 GB ext4 image for non-POSIX filesystems
MOUNT_TMP="/mnt/contest-deploy-target"
RUNTIME_VERSION_VALUE="${RUNTIME_VERSION:-dev}"

_log()  { local ts; ts=$(date -u +%H:%M:%S); echo "[${ts}] $*" | tee -a "${LOG}"; }
_warn() { _log "WARN: $*"; }
_die()  { _log "FATAL: $*" >&2; exit 1; }

need_portable_tool() {
    local tool="$1"
    command -v "${tool}" >/dev/null 2>&1 || _die "Falta herramienta requerida para modo portable: ${tool}"
}

mkdir -p "$(dirname "${LOG}")"
[ "$(id -u)" -eq 0 ] || _die "Must run as root"

cleanup_mount() {
    if mountpoint -q "${MOUNT_TMP}" 2>/dev/null; then
        umount "${MOUNT_TMP}" || true
    fi
}
trap cleanup_mount EXIT

CONTEST_DIR="$(cmdline_param contest_dir)"
CONTEST_ROOT="$(cmdline_param contest_root)"
CONTEST_DIR="$(normalize_contest_dir "${CONTEST_DIR:-/contest}")"
CONTEST_ROOT="${CONTEST_ROOT:-filesystem.squashfs}"

SOURCE_DIR="/run/contest-media${CONTEST_DIR}"

# ----------------------------------------------------------------
# Only deploy when booted from ISO (iso9660).
# ----------------------------------------------------------------
BOOT_FSTYPE="$(awk '$2=="/run/contest-media" {print $3; exit}' /proc/mounts)"
if [ "${BOOT_FSTYPE}" != "iso9660" ]; then
    _log "Boot media is '${BOOT_FSTYPE}' (not iso9660). Nothing to deploy."
    exit 0
fi

[ -f "${SOURCE_DIR}/${CONTEST_ROOT}" ] || \
    _die "Source squashfs not found: ${SOURCE_DIR}/${CONTEST_ROOT}"

_log "ISO boot detected. Starting deployment."
_log "Portable mode: the target partition will NOT be reformatted."
_log "Portable mode: files will be copied inside ${CONTEST_DIR} on the existing filesystem."

# ----------------------------------------------------------------
# Resolve target partition
# ----------------------------------------------------------------
DEPLOY_TARGET="$(cmdline_param contest.deploy_target)"
TARGET_DEV="${DEPLOY_TARGET:-${1:-}}"

# Probe a partition: must be mountable and have enough free space.
# Returns the filesystem type on stdout. Skips swap and ISO device.
probe_partition() {
    local dev="$1"
    local fstype
    fstype="$(lsblk -n -o FSTYPE "${dev}" 2>/dev/null | head -1)"

    case "${fstype}" in
        ext4|ext3|xfs|ntfs|ntfs3|vfat|exfat) ;;
        *) return 1 ;;
    esac

    local mnt_opt
    mnt_opt="$(mount_opts_for_fstype "${fstype}" ro)"

    mkdir -p "${MOUNT_TMP}"
    mount -t "${fstype}" -o "${mnt_opt}" "${dev}" "${MOUNT_TMP}" 2>/dev/null || return 1

    local free_mb
    free_mb=$(df -m "${MOUNT_TMP}" --output=avail 2>/dev/null | tail -1 | tr -d ' ')
    umount "${MOUNT_TMP}"

    [ "${free_mb:-0}" -ge "${MIN_FREE_MB}" ] || return 1
    echo "${fstype}"
}

find_target_partition() {
    _log "Scanning for a suitable partition (>= ${MIN_FREE_MB} MB free)..."
    while IFS= read -r line; do
        local name mountpoint
        name=$(awk '{print $1}' <<< "${line}")
        mountpoint=$(awk '{print $3}' <<< "${line}")

        case "${mountpoint}" in
            /|/boot|/boot/efi|/run/*|/proc|/sys|/dev|/tmp) continue ;;
        esac

        local blkdev="/dev/${name}"
        [ -b "${blkdev}" ] || continue

        if probe_partition "${blkdev}" >/dev/null 2>&1; then
            echo "${blkdev}"
            return 0
        fi
    done < <(lsblk -l -n -o NAME,FSTYPE,MOUNTPOINT 2>/dev/null)
    return 1
}

if [ -z "${TARGET_DEV}" ]; then
    TARGET_DEV="$(find_target_partition)" || \
        _die "No suitable partition found. Use 'contest.deploy_target=/dev/sdXN' on the kernel cmdline."
fi

[ -b "${TARGET_DEV}" ] || _die "Not a block device: ${TARGET_DEV}"

TARGET_FSTYPE="$(probe_partition "${TARGET_DEV}")" || \
    _die "Cannot probe partition ${TARGET_DEV} (unsupported fs or not enough space)"

OVERLAY_IMG_SIZE_MB="$(overlay_img_size_mb_for_fstype "${TARGET_FSTYPE}" "${OVERLAY_IMG_SIZE_MB}")"

_log "Target: ${TARGET_DEV} (${TARGET_FSTYPE})"
_log "Target filesystem will be preserved as-is."

# ----------------------------------------------------------------
# Idempotency
# ----------------------------------------------------------------
local_mnt_opt="$(mount_opts_for_fstype "${TARGET_FSTYPE}" rw)"

mkdir -p "${MOUNT_TMP}"
mount -t "${TARGET_FSTYPE}" -o ro "${TARGET_DEV}" "${MOUNT_TMP}" || \
    _die "Cannot read-mount ${TARGET_DEV}"

if [ -f "${MOUNT_TMP}${CONTEST_DIR}/${MARKER}" ]; then
    _log "Already deployed to ${TARGET_DEV} — nothing to do."
    exit 0
fi
cleanup_mount

# ----------------------------------------------------------------
# Validate free space
# ----------------------------------------------------------------
mount -t "${TARGET_FSTYPE}" -o "${local_mnt_opt}" "${TARGET_DEV}" "${MOUNT_TMP}" || \
    _die "Cannot write-mount ${TARGET_DEV}"

free_mb=$(df -m "${MOUNT_TMP}" --output=avail 2>/dev/null | tail -1 | tr -d ' ')
sqfs_mb=$(du -sm "${SOURCE_DIR}/${CONTEST_ROOT}" 2>/dev/null | awk '{print $1}')
overlay_storage_mb="$(overlay_storage_mb_for_fstype "${TARGET_FSTYPE}" "${OVERLAY_IMG_SIZE_MB}")"
required_mb=$(( sqfs_mb + 256 + overlay_storage_mb ))

if [ "${free_mb:-0}" -lt "${required_mb}" ]; then
    _die "Not enough space on ${TARGET_DEV}: ${free_mb} MB free, ${required_mb} MB needed."
fi
_log "Space OK: ${free_mb} MB free, ${required_mb} MB needed."

# ----------------------------------------------------------------
# Copy contest files
# ----------------------------------------------------------------
_log "Copying contest files..."
mkdir -p "${MOUNT_TMP}${CONTEST_DIR}"

contest_root="${MOUNT_TMP}${CONTEST_DIR}"
current_dir="$(contest_current_dir "${contest_root}")"
staging_dir="$(contest_staging_dir "${contest_root}")"
state_dir="$(contest_state_dir "${contest_root}")"

rm -rf "${current_dir}"
mkdir -p "${current_dir}" "${staging_dir}" "${state_dir}"

for f in vmlinuz initrd.img "${CONTEST_ROOT}"; do
    _log "  → ${f}"
    cp "${SOURCE_DIR}/${f}" "${current_dir}/${f}"
done
if [ -f "${SOURCE_DIR}/grub-entry.cfg" ]; then
    cp "${SOURCE_DIR}/grub-entry.cfg" "${current_dir}/grub-entry.cfg"
fi
write_runtime_version "${contest_root}" "${RUNTIME_VERSION_VALUE}"
printf '%s\n' "${RUNTIME_VERSION_VALUE}" > "${current_dir}/VERSION"
link_runtime_files "${contest_root}"
_log "Files copied."

# ----------------------------------------------------------------
# Overlay storage
# ext4/xfs  → overlayfs can use dirs directly (supports xattr)
# everything else (NTFS, vfat…) → create a loopback ext4 image
# ----------------------------------------------------------------
OVERLAY_IMG_CREATED=0
case "${TARGET_FSTYPE}" in
    ext4|ext3|xfs)
        _log "Native filesystem — overlay dirs will be created by initramfs at boot."
        ;;
    *)
        need_portable_tool truncate
        need_portable_tool mkfs.ext4
        OVERLAY_IMG="${MOUNT_TMP}${CONTEST_DIR}/overlay.img"
        _log "Filesystem ${TARGET_FSTYPE} does not support native overlayfs."
        _log "Portable mode will use ${CONTEST_DIR}/overlay.img to preserve compatibility with the existing partition."
        _log "Non-POSIX filesystem — creating ${OVERLAY_IMG_SIZE_MB} MB ext4 overlay image..."
        truncate -s "${OVERLAY_IMG_SIZE_MB}M" "${OVERLAY_IMG}" || \
            _die "Cannot create overlay.img"
        mkfs.ext4 -q -L contest-overlay "${OVERLAY_IMG}" || \
            _die "mkfs.ext4 failed on overlay.img"
        OVERLAY_IMG_CREATED=1
        _log "overlay.img created."
        ;;
esac

# ----------------------------------------------------------------
# Write marker — must be last (signals complete successful deploy)
# ----------------------------------------------------------------
cat > "${MOUNT_TMP}${CONTEST_DIR}/${MARKER}" <<MARKER
INSTALLED_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TARGET_DEV=${TARGET_DEV}
TARGET_FSTYPE=${TARGET_FSTYPE}
OVERLAY_IMG_CREATED=${OVERLAY_IMG_CREATED}
CONTEST_DIR=${CONTEST_DIR}
CONTEST_ROOT=${CONTEST_ROOT}
RUNTIME_VERSION=${RUNTIME_VERSION_VALUE}
MARKER

cleanup_mount
_log "Deployment complete. Reboot — the ISO GRUB will now show the HDD boot option."
