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

. /usr/lib/contest/lib/base.sh
. /usr/lib/contest/lib/fs.sh
. /usr/lib/contest/lib/progress.sh
. /usr/lib/contest/lib/runtime-layout.sh

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

mount_target() {
    local mode="$1"
    local mnt_opt

    mnt_opt="$(mount_opts_for_fstype "${TARGET_FSTYPE}" "${mode}")"
    mkdir -p "${MOUNT_TMP}"
    mount -t "${TARGET_FSTYPE}" -o "${mnt_opt}" "${TARGET_DEV}" "${MOUNT_TMP}"
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

# Never deploy to USB storage, including USB disks whose partitions are
# reported as non-removable. Check the complete block-device ancestry because
# TRAN is commonly set on the parent disk rather than on the partition.
is_usb_storage() {
    local dev="$1"
    local sysfs_path

    if lsblk -s -n -o TRAN "${dev}" 2>/dev/null | grep -Fqx usb; then
        return 0
    fi

    if command -v udevadm >/dev/null 2>&1 &&
       udevadm info --query=property --name="${dev}" 2>/dev/null |
           grep -Fqx 'ID_BUS=usb'; then
        return 0
    fi

    sysfs_path="$(readlink -f "/sys/class/block/${dev##*/}" 2>/dev/null || true)"
    case "${sysfs_path}" in
        */usb[0-9]*/*) return 0 ;;
    esac

    return 1
}

# Evaluate a partition and populate EVAL_* fields for probing and summaries.
evaluate_partition() {
    local dev="$1"
    local mnt_opt stats

    EVAL_FSTYPE="$(lsblk -n -o FSTYPE "${dev}" 2>/dev/null | head -1)"
    EVAL_SIZE="$(lsblk -n -o SIZE "${dev}" 2>/dev/null | head -1 | tr -d ' ')"
    EVAL_USED="-"
    EVAL_FREE="-"
    EVAL_FREE_MB=0
    EVAL_REASON=""

    if is_usb_storage "${dev}"; then
        EVAL_REASON="NO (USB/externo)"
        return 1
    fi

    case "${EVAL_FSTYPE}" in
        ext4|ext3|xfs|ntfs|ntfs3|vfat|exfat) ;;
        *)
            EVAL_REASON="NO (formato no compatible)"
            return 1
            ;;
    esac

    mnt_opt="$(mount_opts_for_fstype "${EVAL_FSTYPE}" ro)"
    mkdir -p "${MOUNT_TMP}"
    if ! mount -t "${EVAL_FSTYPE}" -o "${mnt_opt}" "${dev}" "${MOUNT_TMP}" 2>/dev/null; then
        EVAL_REASON="NO (bloqueado/no montable)"
        return 1
    fi

    stats="$(df -h "${MOUNT_TMP}" --output=used,avail 2>/dev/null | tail -1)"
    EVAL_USED="$(awk '{print $1}' <<< "${stats}")"
    EVAL_FREE="$(awk '{print $2}' <<< "${stats}")"
    EVAL_FREE_MB="$(df -m "${MOUNT_TMP}" --output=avail 2>/dev/null | tail -1 | tr -d ' ')"
    if ! umount "${MOUNT_TMP}"; then
        EVAL_REASON="NO (no se pudo desmontar)"
        return 1
    fi

    if [ "${EVAL_FREE_MB:-0}" -lt "${MIN_FREE_MB}" ]; then
        EVAL_REASON="NO (sin espacio)"
        return 1
    fi

    # A read-only probe is insufficient for NTFS volumes affected by Windows
    # hibernation/Fast Startup. Verify that the candidate can actually be
    # mounted read-write before selecting it.
    mnt_opt="$(mount_opts_for_fstype "${EVAL_FSTYPE}" rw)"
    if ! mount -t "${EVAL_FSTYPE}" -o "${mnt_opt}" "${dev}" "${MOUNT_TMP}" 2>/dev/null; then
        EVAL_REASON="NO (bloqueado/solo lectura)"
        return 1
    fi
    if ! umount "${MOUNT_TMP}"; then
        EVAL_REASON="NO (no se pudo desmontar)"
        return 1
    fi

    EVAL_REASON="SI"
    return 0
}

# Probe a partition: must be readable, writable and have enough free space.
# Returns the filesystem type on stdout.
probe_partition() {
    local dev="$1"

    evaluate_partition "${dev}" || return 1
    echo "${EVAL_FSTYPE}"
}

find_target_partition() {
    local selected=""
    local selected_free_mb=0

    # This function is consumed through command substitution, so diagnostics
    # must stay off stdout; stdout is reserved for the selected device path.
    _log "Scanning internal disks for a suitable partition (>= ${MIN_FREE_MB} MB free)..." >&2
    printf '\n%-16s %-8s %-9s %-9s %-9s %s\n' \
        "DISPOSITIVO" "FORMATO" "TAMAÑO" "USADO" "LIBRE" "ELEGIBLE" >&2
    printf '%-16s %-8s %-9s %-9s %-9s %s\n' \
        "----------------" "--------" "---------" "---------" "---------" "------------------------" >&2

    while IFS= read -r line; do
        local name mountpoint
        name=$(awk '{print $1}' <<< "${line}")
        mountpoint=$(awk '{print $3}' <<< "${line}")

        case "${mountpoint}" in
            /|/boot|/boot/efi|/run/*|/proc|/sys|/dev|/tmp) continue ;;
        esac

        local blkdev="/dev/${name}"
        [ -b "${blkdev}" ] || continue

        if evaluate_partition "${blkdev}"; then
            if [ "${EVAL_FREE_MB:-0}" -gt "${selected_free_mb}" ]; then
                selected="${blkdev}"
                selected_free_mb="${EVAL_FREE_MB}"
            fi
        fi

        printf '%-16s %-8s %-9s %-9s %-9s %s\n' \
            "${blkdev}" "${EVAL_FSTYPE:--}" "${EVAL_SIZE:--}" \
            "${EVAL_USED:--}" "${EVAL_FREE:--}" "${EVAL_REASON}" >&2
    done < <(lsblk -l -n -o NAME,FSTYPE,MOUNTPOINT 2>/dev/null)

    printf '\n' >&2
    [ -n "${selected}" ] || return 1
    _log "Selected ${selected} with ${selected_free_mb} MB free." >&2
    echo "${selected}"
}

if [ -z "${TARGET_DEV}" ]; then
    TARGET_DEV="$(find_target_partition)" || \
        _die "No writable internal partition with enough free space was found. USB storage is not eligible."
fi

[ -b "${TARGET_DEV}" ] || _die "Not a block device: ${TARGET_DEV}"
is_usb_storage "${TARGET_DEV}" && \
    _die "Refusing USB storage target: ${TARGET_DEV}. Select an internal disk partition."

TARGET_FSTYPE="$(probe_partition "${TARGET_DEV}")" || \
    _die "Cannot probe partition ${TARGET_DEV} (unsupported fs or not enough space)"

OVERLAY_IMG_SIZE_MB="$(overlay_img_size_mb_for_fstype "${TARGET_FSTYPE}" "${OVERLAY_IMG_SIZE_MB}")"

_log "Target: ${TARGET_DEV} (${TARGET_FSTYPE})"
_log "Target filesystem will be preserved as-is."

# ----------------------------------------------------------------
# Idempotency
# ----------------------------------------------------------------
mount_target ro || \
    _die "Cannot read-mount ${TARGET_DEV}"

if [ -f "${MOUNT_TMP}${CONTEST_DIR}/${MARKER}" ]; then
    _log "Already deployed to ${TARGET_DEV} — nothing to do."
    exit 0
fi
cleanup_mount

# ----------------------------------------------------------------
# Validate free space
# ----------------------------------------------------------------
if ! mount_target rw; then
    if [ "${TARGET_FSTYPE}" = "ntfs" ] || [ "${TARGET_FSTYPE}" = "ntfs3" ]; then
        echo "" >&2
        echo "=========================================================================" >&2
        echo " ¡ERROR: LA PARTICIÓN DE WINDOWS ESTÁ SECUESTRADA / BLOQUEADA!" >&2
        echo "=========================================================================" >&2
        echo " Se detectó que el Inicio Rápido de Windows o la hibernación están activos." >&2
        echo " No se puede escribir en el disco en este estado para evitar pérdida de datos." >&2
        echo "" >&2
        echo " Por favor, realiza lo siguiente:" >&2
        echo "   1. Reinicia la máquina e inicia Windows normalmente." >&2
        echo "   2. Apaga Windows manteniendo presionada la tecla SHIFT (Mayús)." >&2
        echo "      (O desactiva el 'Inicio Rápido' desde el Panel de Control)." >&2
        echo "   3. Vuelve a iniciar con este medio USB." >&2
        echo "=========================================================================" >&2
        echo "" >&2
        read -r -p "Presiona Enter para salir del instalador..." || true
        exit 1
    else
        _die "Cannot write-mount ${TARGET_DEV}"
    fi
fi

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
    copy_file_with_progress "${SOURCE_DIR}/${f}" "${current_dir}/${f}" "${f}" || \
        _die "Failed to copy ${f}"
done
if [ -f "${SOURCE_DIR}/grub-entry.cfg" ]; then
    _log "  → grub-entry.cfg"
    copy_file_with_progress \
        "${SOURCE_DIR}/grub-entry.cfg" \
        "${current_dir}/grub-entry.cfg" \
        "grub-entry.cfg" || _die "Failed to copy grub-entry.cfg"
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
        mkfs.ext4 -q -E nodiscard,lazy_itable_init=0,lazy_journal_init=0 -L contest-overlay "${OVERLAY_IMG}" || \
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
