#!/usr/bin/env bash

set -euo pipefail

. /usr/lib/contest/lib/base.sh
. /usr/lib/contest/lib/fs.sh
. /usr/lib/contest/lib/runtime-layout.sh

LOG="/var/log/contest-overlay-provision.log"
OVERLAY_IMG_SIZE_MB=4096
MOUNT_TMP="/mnt/contest-overlay-provision"
OVERLAY_CHECK_TMP="/mnt/contest-overlay-check"

_log() {
    local ts
    ts=$(date -u +%H:%M:%S)
    echo "[${ts}] $*" | tee -a "${LOG}"
}

_die() {
    _log "FATAL: $*"
    exit 1
}

mkdir -p "$(dirname "${LOG}")"
[ "$(id -u)" -eq 0 ] || _die "Must run as root"

if mountpoint -q /run/contest-overlay 2>/dev/null; then
    _log "overlay.img ya esta montado en /run/contest-overlay; no se modificara."
    exit 0
fi

cleanup_mount() {
    if mountpoint -q "${MOUNT_TMP}" 2>/dev/null; then
        umount "${MOUNT_TMP}" || true
    fi

    if mountpoint -q "${OVERLAY_CHECK_TMP}" 2>/dev/null; then
        umount "${OVERLAY_CHECK_TMP}" || true
    fi
}
trap cleanup_mount EXIT

overlay_img_is_valid() {
    local image_path="$1"

    mkdir -p "${OVERLAY_CHECK_TMP}"
    if mount -o ro,loop "${image_path}" "${OVERLAY_CHECK_TMP}" 2>/dev/null; then
        umount "${OVERLAY_CHECK_TMP}" 2>/dev/null || true
        return 0
    fi

    return 1
}

CONTEST_DIR="$(cmdline_param contest_dir)"
CONTEST_DIR="$(normalize_contest_dir "${CONTEST_DIR:-/contest}")"
CONTEST_ROOT="$(cmdline_param contest_root)"
CONTEST_ROOT="${CONTEST_ROOT:-filesystem.squashfs}"

BOOT_DEV=""
BOOT_FSTYPE=""
MEDIA_ROOT=""

BOOT_LINE="$(awk '$2=="/run/contest-media" {print $1 "|" $3; exit}' /proc/mounts)"
if [ -n "${BOOT_LINE}" ]; then
    BOOT_DEV="${BOOT_LINE%%|*}"
    BOOT_FSTYPE="${BOOT_LINE#*|}"
    MEDIA_ROOT="/run/contest-media"
fi

if [ "${BOOT_FSTYPE}" = "iso9660" ]; then
    BOOT_DEV=""
    BOOT_FSTYPE=""
    MEDIA_ROOT=""
fi

find_portable_runtime() {
    local dev fstype

    mkdir -p "${MOUNT_TMP}"
    while IFS= read -r line; do
        dev="/dev/$(awk '{print $1}' <<< "${line}")"
        fstype="$(awk '{print $2}' <<< "${line}")"

        case "${fstype}" in
            ext4|ext3|xfs|ntfs|ntfs3|vfat|exfat) ;;
            *) continue ;;
        esac

        mount -t "${fstype}" -o "$(mount_opts_for_fstype "${fstype}" ro)" "${dev}" "${MOUNT_TMP}" 2>/dev/null || continue
        if [ -f "${MOUNT_TMP}${CONTEST_DIR}/.contest-installed" ]; then
            BOOT_DEV="${dev}"
            BOOT_FSTYPE="${fstype}"
            MEDIA_ROOT="${MOUNT_TMP}"
            return 0
        fi
        cleanup_mount
    done < <(lsblk -l -n -o NAME,FSTYPE 2>/dev/null)

    return 1
}

[ -n "${MEDIA_ROOT}" ] || find_portable_runtime || {
    _log "No se encontro una instalacion portable para preparar persistencia."
    exit 0
}

case "${BOOT_FSTYPE}" in
    iso9660|ext4|ext3|xfs)
        _log "${BOOT_FSTYPE} ya tiene persistencia soportada o no aplica."
        exit 0
        ;;
    ntfs|ntfs3|vfat|exfat)
        ;;
    *)
        _log "Filesystem ${BOOT_FSTYPE} no soportado para aprovisionamiento automatico."
        exit 0
        ;;
esac

OVERLAY_IMG_SIZE_MB="$(overlay_img_size_mb_for_fstype "${BOOT_FSTYPE}" "${OVERLAY_IMG_SIZE_MB}")"

OVERLAY_IMG="${MEDIA_ROOT}${CONTEST_DIR}/overlay.img"
if [ -e "${OVERLAY_IMG}" ]; then
    if overlay_img_is_valid "${OVERLAY_IMG}"; then
        _log "overlay.img ya existe y es valido; nada que hacer."
        if [ ! -f "${MEDIA_ROOT}${CONTEST_DIR}/.contest-installed" ]; then
            _log "Marker portable ausente; se recreara."
            cat > "${MEDIA_ROOT}${CONTEST_DIR}/.contest-installed" <<EOF
INSTALLED_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TARGET_DEV=${BOOT_DEV}
TARGET_FSTYPE=${BOOT_FSTYPE}
OVERLAY_IMG_CREATED=1
CONTEST_DIR=${CONTEST_DIR}
CONTEST_ROOT=${CONTEST_ROOT}
EOF
        fi
        exit 0
    fi

    _log "overlay.img existe pero no es valido; se recreara."
    rm -f "${OVERLAY_IMG}" || _die "No se pudo eliminar overlay.img invalido"
fi

command -v truncate >/dev/null 2>&1 || _die "truncate no disponible"
command -v mkfs.ext4 >/dev/null 2>&1 || _die "mkfs.ext4 no disponible"

if [ "${MEDIA_ROOT}" = "/run/contest-media" ]; then
    if ! mount -o remount,"$(mount_opts_for_fstype "${BOOT_FSTYPE}" rw)" /run/contest-media 2>/dev/null; then
        _log "No se pudo remount rw /run/contest-media; se mantiene sin persistencia."
        exit 0
    fi
else
    cleanup_mount
    mkdir -p "${MOUNT_TMP}"
    if ! mount -t "${BOOT_FSTYPE}" -o "$(mount_opts_for_fstype "${BOOT_FSTYPE}" rw)" "${BOOT_DEV}" "${MOUNT_TMP}" 2>/dev/null; then
        _log "No se pudo montar ${BOOT_DEV} en modo rw; se mantiene sin persistencia."
        exit 0
    fi
    MEDIA_ROOT="${MOUNT_TMP}"
    OVERLAY_IMG="${MEDIA_ROOT}${CONTEST_DIR}/overlay.img"
fi

mkdir -p "${MEDIA_ROOT}${CONTEST_DIR}"
_log "Creando overlay.img persistente en ${CONTEST_DIR} (${OVERLAY_IMG_SIZE_MB} MB)..."
truncate -s "${OVERLAY_IMG_SIZE_MB}M" "${OVERLAY_IMG}" || _die "No se pudo crear overlay.img"
mkfs.ext4 -q -E nodiscard,lazy_itable_init=0,lazy_journal_init=0 -L contest-overlay "${OVERLAY_IMG}" || _die "mkfs.ext4 fallo sobre overlay.img"

cat > "${MEDIA_ROOT}${CONTEST_DIR}/.contest-installed" <<EOF
INSTALLED_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TARGET_DEV=${BOOT_DEV}
TARGET_FSTYPE=${BOOT_FSTYPE}
OVERLAY_IMG_CREATED=1
CONTEST_DIR=${CONTEST_DIR}
CONTEST_ROOT=${CONTEST_ROOT}
EOF

_log "overlay.img creado correctamente en ${BOOT_DEV}."
_log "Reinicia una vez mas para que /home y otros cambios queden persistentes."
