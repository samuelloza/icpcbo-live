#!/bin/bash
# full-install.sh — Instala el sistema contest desde USB a disco local.
#
# Descomprime filesystem.squashfs en una partición ext4, copia kernel e initrd,
# instala GRUB en el disco y escribe el marcador .contest-full-installed.
# Después del reinicio, el sistema arranca completamente desde el disco.
# El USB puede retirarse.
#
# Disparado por: contest-full-install.service (ConditionKernelCommandLine=contest.install_mode=full)
#
# Usage: full-install.sh [TARGET_DISK]
# Override vía kernel cmdline: contest.install_target=/dev/sdX

set -euo pipefail

. /usr/lib/contest/common.sh

[ -r /etc/contestiso/update.env ] && . /etc/contestiso/update.env

LOG="/var/log/contest-full-install.log"
MOUNT_TMP="/mnt/contest-full-install"
MARKER=".contest-full-installed"
EFI_SIZE_MB=512
MIN_DISK_GB=8
RUNTIME_VERSION_VALUE="${RUNTIME_VERSION:-dev}"

TOTAL_STEPS=7

_log()  { local ts; ts=$(date -u +%H:%M:%S); echo "[${ts}] $*" | tee -a "${LOG}"; }

_warn() {
    echo "" | tee -a "${LOG}"
    echo "  ⚠  ADVERTENCIA: $*" | tee -a "${LOG}"
}

_ok() {
    echo "  ✓  $*" | tee -a "${LOG}"
}

_step() {
    local num="$1"; shift
    echo "" | tee -a "${LOG}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "${LOG}"
    printf "  [%d/%d] %s\n" "${num}" "${TOTAL_STEPS}" "$*" | tee -a "${LOG}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "${LOG}"
}

_die() {
    echo "" | tee -a "${LOG}"
    echo "╔══════════════════════════════════════════════════╗" | tee -a "${LOG}"
    echo "║              ERROR — INSTALACION DETENIDA        ║" | tee -a "${LOG}"
    echo "╚══════════════════════════════════════════════════╝" | tee -a "${LOG}"
    echo "" | tee -a "${LOG}"
    echo "  ✗  $*" | tee -a "${LOG}"
    echo "" | tee -a "${LOG}"
    echo "  Log completo en: ${LOG}" | tee -a "${LOG}"
    if [ -n "${STATE_DIR:-}" ] && [ -d "${STATE_DIR}" ]; then
        cp -a "${LOG}" "${STATE_DIR}/full-install.log" 2>/dev/null || true
    fi
    exit 1
}

_copy_file() {
    local src="$1" dst="$2"
    local label size_mb
    label="$(basename "${dst}")"
    size_mb="$(du -sm "${src}" 2>/dev/null | awk '{print $1}')"
    echo "  → ${label}  (${size_mb} MB)" | tee -a "${LOG}"
    dd if="${src}" of="${dst}" bs=4M status=progress 2>&1 \
        | grep -v '^$' | tee -a "${LOG}" || true
    echo "" | tee -a "${LOG}"
}

mkdir -p "$(dirname "${LOG}")"
[ "$(id -u)" -eq 0 ] || _die "Must run as root"

echo "" | tee -a "${LOG}"
echo "╔══════════════════════════════════════════════════╗" | tee -a "${LOG}"
echo "║     ICPC Bolivia — Instalación en disco          ║" | tee -a "${LOG}"
echo "╚══════════════════════════════════════════════════╝" | tee -a "${LOG}"
echo "" | tee -a "${LOG}"

BOOT_FSTYPE="$(awk '$2=="/run/contest-media" {print $3; exit}' /proc/mounts)"
if [ "${BOOT_FSTYPE}" != "iso9660" ]; then
    _log "Boot media es '${BOOT_FSTYPE}' (no iso9660). Nada que instalar."
    exit 0
fi

CONTEST_DIR="$(cmdline_param contest_dir)"
CONTEST_ROOT="$(cmdline_param contest_root)"
CONTEST_DIR="$(normalize_contest_dir "${CONTEST_DIR:-/contest}")"
CONTEST_ROOT="${CONTEST_ROOT:-filesystem.squashfs}"
SOURCE_DIR="/run/contest-media${CONTEST_DIR}"
SQUASHFS="${SOURCE_DIR}/${CONTEST_ROOT}"

[ -f "${SQUASHFS}" ] || _die "Squashfs no encontrado: ${SQUASHFS}"

IS_EFI=0
[ -d /sys/firmware/efi ] && IS_EFI=1
_log "Modo de arranque: $([ "${IS_EFI}" = "1" ] && echo UEFI || echo BIOS)"

cleanup_mounts() {
    for mp in \
        "${MOUNT_TMP}/boot/efi" \
        "${MOUNT_TMP}/run" \
        "${MOUNT_TMP}/sys" \
        "${MOUNT_TMP}/proc" \
        "${MOUNT_TMP}/dev/pts" \
        "${MOUNT_TMP}/dev" \
        "${MOUNT_TMP}"; do
        mountpoint -q "${mp}" 2>/dev/null && umount -lf "${mp}" || true
    done
    rmdir "${MOUNT_TMP}" 2>/dev/null || true
}
trap cleanup_mounts EXIT

find_target_disk() {
    while IFS= read -r line; do
        local name size rm
        name=$(echo "${line}" | awk '{print $1}')
        size=$(echo "${line}" | awk '{print $2}')
        rm=$(echo "${line}" | awk '{print $3}')

        [ "${rm}" = "1" ] && continue
        [ -z "${size}" ] && continue

        local size_gb=$(( size / 1024 / 1024 / 1024 ))
        [ "${size_gb}" -ge "${MIN_DISK_GB}" ] || continue

        local blkdev="/dev/${name}"
        [ -b "${blkdev}" ] || continue
        echo "${blkdev}"
        return 0
    done < <(lsblk -d -n -b -o NAME,SIZE,RM 2>/dev/null | sort -k2 -n -r)
    return 1
}

INSTALL_TARGET="$(cmdline_param contest.install_target)"
TARGET_DISK="${INSTALL_TARGET:-${1:-}}"

if [ -z "${TARGET_DISK}" ]; then
    _log "Buscando disco de instalacion (>= ${MIN_DISK_GB} GB)..."
    TARGET_DISK="$(find_target_disk)" || \
        _die "Sin disco adecuado. Usa 'contest.install_target=/dev/sdX' en el cmdline."
fi

[ -b "${TARGET_DISK}" ] || _die "No es un dispositivo de bloque: ${TARGET_DISK}"

DISK_SIZE_GB=$(lsblk -d -n -b -o SIZE "${TARGET_DISK}" 2>/dev/null | awk '{printf "%d", $1/1024/1024/1024}')
[ "${DISK_SIZE_GB:-0}" -ge "${MIN_DISK_GB}" ] || _die "Disco muy pequeño: ${DISK_SIZE_GB} GB (se necesitan ${MIN_DISK_GB} GB)"

_log "Disco destino: ${TARGET_DISK} (${DISK_SIZE_GB} GB)"

mkdir -p "${MOUNT_TMP}"
for fstype in ext4 xfs ext3; do
    if mount -t "${fstype}" -o ro "${TARGET_DISK}"?* /run/contest-scan 2>/dev/null; then
        if [ -f "/run/contest-scan${CONTEST_DIR}/${MARKER}" ]; then
            umount /run/contest-scan 2>/dev/null || true
            _log "Instalación completa ya detectada en ${TARGET_DISK}. Nada que hacer."
            exit 0
        fi
        umount /run/contest-scan 2>/dev/null || true
        break
    fi
done 2>/dev/null || true

_step 1 "Particionando disco ${TARGET_DISK}"
wipefs -a "${TARGET_DISK}" 2>/dev/null || true
sleep 1

part_name() {
    local disk="$1" idx="$2"
    if echo "${disk}" | grep -qE 'nvme|mmcblk'; then
        echo "${disk}p${idx}"
    else
        echo "${disk}${idx}"
    fi
}

if [ "${IS_EFI}" = "1" ]; then
    parted -s "${TARGET_DISK}" mklabel gpt mkpart ESP fat32 1MiB "${EFI_SIZE_MB}MiB" set 1 esp on mkpart root ext4 "${EFI_SIZE_MB}MiB" 100%
    partprobe "${TARGET_DISK}" 2>/dev/null || true
    sleep 2

    EFI_PART="$(part_name "${TARGET_DISK}" 1)"
    ROOT_PART="$(part_name "${TARGET_DISK}" 2)"

    _ok "Tabla GPT creada"
    echo "  → Formateando EFI  (${EFI_PART})..." | tee -a "${LOG}"
    mkfs.vfat -F32 -n EFI "${EFI_PART}" || _die "mkfs.vfat falló en ${EFI_PART}"
    echo "  → Formateando root (${ROOT_PART})..." | tee -a "${LOG}"
    mkfs.ext4 -F -L contest-root "${ROOT_PART}" 2>&1 | tee -a "${LOG}" || _die "mkfs.ext4 falló en ${ROOT_PART}"
else
    parted -s "${TARGET_DISK}" mklabel msdos mkpart primary ext4 1MiB 100% set 1 boot on
    partprobe "${TARGET_DISK}" 2>/dev/null || true
    sleep 2

    ROOT_PART="$(part_name "${TARGET_DISK}" 1)"
    EFI_PART=""

    _ok "Tabla MBR creada"
    echo "  → Formateando root (${ROOT_PART})..." | tee -a "${LOG}"
    mkfs.ext4 -F -L contest-root "${ROOT_PART}" 2>&1 | tee -a "${LOG}" || _die "mkfs.ext4 falló en ${ROOT_PART}"
fi

ROOT_UUID="$(blkid -s UUID -o value "${ROOT_PART}")"
[ -n "${ROOT_UUID}" ] || _die "No se pudo obtener UUID de ${ROOT_PART}"
_ok "Disco particionado  →  root: ${ROOT_PART}  UUID: ${ROOT_UUID}"

mkdir -p "${MOUNT_TMP}"
mount -t ext4 "${ROOT_PART}" "${MOUNT_TMP}" || _die "No se pudo montar ${ROOT_PART}"

_step 2 "Descomprimiendo sistema al disco"
echo "  Origen:  ${SQUASHFS}  ($(du -sh "${SQUASHFS}" 2>/dev/null | awk '{print $1}'))" | tee -a "${LOG}"
echo "  Destino: ${MOUNT_TMP}" | tee -a "${LOG}"
echo "  (esto puede tardar varios minutos...)" | tee -a "${LOG}"
echo "" | tee -a "${LOG}"

unsquashfs -f -d "${MOUNT_TMP}" "${SQUASHFS}" 2>&1 | tee -a "${LOG}" || _die "unsquashfs falló"

_ok "Sistema descomprimido"

echo "" | tee -a "${LOG}"
echo "  Archivos instalados en ${MOUNT_TMP}:" | tee -a "${LOG}"
ls -la "${MOUNT_TMP}" 2>&1 | tee -a "${LOG}"

_step 3 "Copiando kernel e initrd"
mkdir -p "${MOUNT_TMP}/boot"
mkdir -p "${MOUNT_TMP}${CONTEST_DIR}"

contest_root="${MOUNT_TMP}${CONTEST_DIR}"
current_dir="$(contest_current_dir "${contest_root}")"
staging_dir="$(contest_staging_dir "${contest_root}")"
state_dir="$(contest_state_dir "${contest_root}")"
STATE_DIR="${state_dir}"
rm -rf "${current_dir}"
mkdir -p "${current_dir}" "${staging_dir}" "${state_dir}"

KVER="$(ls -1 "${MOUNT_TMP}/usr/lib/modules/" 2>/dev/null | sort -V | tail -n1)"
[ -n "${KVER}" ] || _die "No se encontró versión de kernel en ${MOUNT_TMP}/usr/lib/modules/"
echo "  Versión del kernel: ${KVER}" | tee -a "${LOG}"

_copy_file "${SOURCE_DIR}/vmlinuz" "${MOUNT_TMP}/boot/vmlinuz-${KVER}"
_copy_file "${SOURCE_DIR}/initrd.img" "${MOUNT_TMP}/boot/initrd.img-${KVER}"
_copy_file "${SOURCE_DIR}/vmlinuz" "${current_dir}/vmlinuz"
_copy_file "${SOURCE_DIR}/initrd.img" "${current_dir}/initrd.img"
_copy_file "${SQUASHFS}" "${current_dir}/filesystem.squashfs"
if [ -f "${SOURCE_DIR}/grub-entry.cfg" ]; then
    cp -a "${SOURCE_DIR}/grub-entry.cfg" "${current_dir}/grub-entry.cfg"
fi
printf '%s\n' "${RUNTIME_VERSION_VALUE}" > "${current_dir}/VERSION"
write_runtime_version "${contest_root}" "${RUNTIME_VERSION_VALUE}"
link_runtime_files "${contest_root}"
cp -a "${LOG}" "${state_dir}/full-install.log" 2>/dev/null || true

ln -sf "vmlinuz-${KVER}" "${MOUNT_TMP}/boot/vmlinuz"
ln -sf "initrd.img-${KVER}" "${MOUNT_TMP}/boot/initrd.img"
_ok "Kernel e initrd copiados"

_step 4 "Configurando sistema instalado"
echo "  → /etc/fstab..." | tee -a "${LOG}"
{
    echo "# /etc/fstab — generado por contest full-install"
    echo "UUID=${ROOT_UUID}  /  ext4  errors=remount-ro  0  1"
    if [ "${IS_EFI}" = "1" ] && [ -n "${EFI_PART}" ]; then
        EFI_UUID="$(blkid -s UUID -o value "${EFI_PART}")"
        echo "UUID=${EFI_UUID}  /boot/efi  vfat  umask=0077  0  1"
    fi
    echo "tmpfs  /tmp  tmpfs  defaults,nosuid,nodev  0  0"
} > "${MOUNT_TMP}/etc/fstab"

echo "  → Removiendo scripts live del initramfs..." | tee -a "${LOG}"
rm -f "${MOUNT_TMP}/etc/initramfs-tools/scripts/local"

echo "  → Preparando /tmp y /var/tmp para update-initramfs..." | tee -a "${LOG}"
mkdir -p "${MOUNT_TMP}/tmp" "${MOUNT_TMP}/var/tmp" "${MOUNT_TMP}/var/log"
chmod 1777 "${MOUNT_TMP}/tmp" "${MOUNT_TMP}/var/tmp"

echo "  → Montando pseudo-filesystems (chroot)..." | tee -a "${LOG}"
mkdir -p "${MOUNT_TMP}/dev" "${MOUNT_TMP}/dev/pts" "${MOUNT_TMP}/proc" "${MOUNT_TMP}/sys" "${MOUNT_TMP}/run"
mount --bind /dev "${MOUNT_TMP}/dev"
mount --bind /dev/pts "${MOUNT_TMP}/dev/pts"
mount -t proc proc "${MOUNT_TMP}/proc"
mount -t sysfs sys "${MOUNT_TMP}/sys"
mount -t tmpfs tmpfs "${MOUNT_TMP}/run"
mkdir -p "${MOUNT_TMP}/run/lock"

if [ "${IS_EFI}" = "1" ] && [ -n "${EFI_PART}" ]; then
    mkdir -p "${MOUNT_TMP}/boot/efi"
    mount -t vfat "${EFI_PART}" "${MOUNT_TMP}/boot/efi" || _die "No se pudo montar ${EFI_PART} en /boot/efi"
fi

cp /etc/resolv.conf "${MOUNT_TMP}/etc/resolv.conf" 2>/dev/null || true
_ok "Sistema configurado"

_step 5 "Regenerando initramfs (boot estándar Debian)"
chroot "${MOUNT_TMP}" update-initramfs -u -k "${KVER}" 2>&1 | tee -a "${LOG}" || _die "update-initramfs falló"
_ok "initramfs regenerado"

_step 6 "Instalando bootloader GRUB"
if [ "${IS_EFI}" = "1" ]; then
    echo "  → Modo UEFI  —  target: x86_64-efi" | tee -a "${LOG}"
    chroot "${MOUNT_TMP}" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="ICPC Bolivia" --recheck 2>&1 | tee -a "${LOG}" || _die "grub-install (EFI) falló"
else
    echo "  → Modo BIOS  —  target: i386-pc  disco: ${TARGET_DISK}" | tee -a "${LOG}"
    chroot "${MOUNT_TMP}" grub-install --target=i386-pc --recheck "${TARGET_DISK}" 2>&1 | tee -a "${LOG}" || _die "grub-install (BIOS) falló"
fi
_ok "GRUB instalado en ${TARGET_DISK}"

echo "  → Generando grub.cfg..." | tee -a "${LOG}"
chroot "${MOUNT_TMP}" update-grub 2>&1 | tee -a "${LOG}" || _warn "update-grub tuvo errores"
_ok "grub.cfg generado"

_step 7 "Finalizando"
printf 'INSTALL_TYPE=full\nINSTALL_DATE=%s\nTARGET_DISK=%s\nROOT_PART=%s\nROOT_UUID=%s\nCONTEST_DIR=%s\nCONTEST_ROOT=%s\nRUNTIME_VERSION=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${TARGET_DISK}" "${ROOT_PART}" "${ROOT_UUID}" "${CONTEST_DIR}" "${CONTEST_ROOT}" "${RUNTIME_VERSION_VALUE}" > "${MOUNT_TMP}${CONTEST_DIR}/${MARKER}"
cp -a "${LOG}" "${state_dir}/full-install.log" 2>/dev/null || true
_ok "Marcador de instalación escrito"

cleanup_mounts
trap - EXIT

echo "" | tee -a "${LOG}"
echo "╔══════════════════════════════════════════════════╗" | tee -a "${LOG}"
echo "║         ✓  INSTALACIÓN COMPLETA                  ║" | tee -a "${LOG}"
echo "╠══════════════════════════════════════════════════╣" | tee -a "${LOG}"
printf "║  Disco:  %-39s ║\n" "${TARGET_DISK}" | tee -a "${LOG}"
printf "║  Part.:  %-39s ║\n" "${ROOT_PART}" | tee -a "${LOG}"
printf "║  UUID:   %-39s ║\n" "${ROOT_UUID}" | tee -a "${LOG}"
echo "╠══════════════════════════════════════════════════╣" | tee -a "${LOG}"
echo "║  Retire el USB y reinicie el equipo.             ║" | tee -a "${LOG}"
echo "║  Log: /var/log/contest-full-install.log          ║" | tee -a "${LOG}"
echo "╚══════════════════════════════════════════════════╝" | tee -a "${LOG}"
echo "" | tee -a "${LOG}"

sleep 5
systemctl reboot
