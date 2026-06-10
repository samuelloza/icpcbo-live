#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_SCRIPT_DIR="${SCRIPT_DIR}/build"

# shellcheck source=./build/lib/common.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=../config/iso.conf
source "${PROJECT_DIR}/config/iso.conf"

resolve_project_path() {
    local path="$1"
    local fallback_path="$2"

    if [[ "${path}" == /work/* ]] && { [[ ! -d /work ]] || [[ ! -w /work ]]; }; then
        path="${fallback_path}"
    fi

    if [[ -e "${path}" ]]; then
        if [[ ! -w "${path}" ]]; then
            path="${fallback_path}"
        fi
    elif [[ ! -w "$(dirname "${path}")" ]]; then
        path="${fallback_path}"
    fi

    printf '%s\n' "${path}"
}

OUTPUT_DIR="$(resolve_project_path "${OUTPUT_DIR}" "${PROJECT_TMP_DIR}/output")"
UPDATES_DIR="$(resolve_project_path "${UPDATES_DIR}" "${PROJECT_TMP_DIR}/updates")"
WORK_DIR="$(resolve_project_path "${WORK_DIR}" "${PROJECT_TMP_DIR}/work")"
ROOTFS_DIR="${WORK_DIR}/rootfs"
RUNTIME_DIR="${WORK_DIR}/runtime"
ISO_STAGING_DIR="${WORK_DIR}/iso-staging"
DOWNLOAD_CACHE_DIR="$(resolve_project_path "${DOWNLOAD_CACHE_DIR}" "${PROJECT_TMP_DIR}/download-cache")"
APT_CACHE_DIR="$(resolve_project_path "${APT_CACHE_DIR}" "${PROJECT_TMP_DIR}/apt-cache")"

# shellcheck source=./build/lib/grub.sh
source "${BUILD_SCRIPT_DIR}/grub.sh"

rootfs_tmp_path() {
    local name="${1-}"
    local path="${ROOTFS_DIR}/tmp"

    if [[ -n "${name}" ]]; then
        path="${path}/${name}"
    fi

    printf '%s\n' "${path}"
}

desktop_setup_dir() {
    local dir="${PROJECT_DIR}/scripts/setup.d/${DESKTOP_PROFILE}"

    [[ -d "${dir}" ]] || die "Perfil de escritorio no encontrado: ${DESKTOP_PROFILE}"
    printf '%s\n' "${dir}"
}

desktop_packages_list() {
    local candidate="$(desktop_setup_dir)/packages.list"

    [[ -f "${candidate}" ]] || die "No existe lista de paquetes: ${candidate}"
    printf '%s\n' "${candidate}"
}

desktop_packages_remove_list() {
    local candidate="$(desktop_setup_dir)/packages-remove.list"

    [[ -f "${candidate}" ]] || die "No existe lista de purga: ${candidate}"
    printf '%s\n' "${candidate}"
}

cleanup() {
    umount_chroot || true
}
trap cleanup EXIT

copy_to_rootfs_tmp() {
    if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
        die "copy_to_rootfs_tmp expects: source [dest_name]"
    fi

    local src="$1"
    local dest_name="${2:-$(basename "${src}")}"

    mkdir -p "$(rootfs_tmp_path)"
    cp "${src}" "$(rootfs_tmp_path "${dest_name}")"
}

copy_setup_hooks() {
    local common_src="${PROJECT_DIR}/scripts/setup.d/common"
    local desktop_src="$(desktop_setup_dir)"
    local dst="$(rootfs_tmp_path "setup.d")"
    local hook

    rm -rf "${dst}"
    mkdir -p "${dst}"

    for hook in "${common_src}"/*.sh "${desktop_src}"/*.sh; do
        [[ -e "${hook}" ]] || continue
        cp -a "${hook}" "${dst}/"
    done
}

# Copia scripts auxiliares del host dentro del chroot para que ambas
# sesiones del chroot puedan usarlos sin duplicar sus definiciones en línea.
copy_chroot_scripts() {
    copy_to_rootfs_tmp "${SCRIPT_DIR}/run-hook-dir.sh"
    copy_to_rootfs_tmp "${SCRIPT_DIR}/cached-curl.sh"
    copy_to_rootfs_tmp "${BUILD_SCRIPT_DIR}/install-and-customize-chroot.sh"
    copy_to_rootfs_tmp "${BUILD_SCRIPT_DIR}/trim-chroot.sh"
}

copy_repo_assets() {
    local src="${PROJECT_DIR}/assets"
    local dst="$(rootfs_tmp_path "assets")"

    rm -rf "${dst}"
    mkdir -p "${dst}"

    if [[ -d "${src}" ]]; then
        cp -a "${src}/." "${dst}/"
    fi

    if [[ -f "${PROJECT_DIR}/desktop-wallpaper.svg" ]]; then
        mkdir -p "${dst}/contestants/misc"
        cp "${PROJECT_DIR}/desktop-wallpaper.svg" \
            "${dst}/contestants/misc/desktop-wallpaper.svg"
    fi
}

copy_chroot_inputs() {
    copy_to_rootfs_tmp "$(desktop_packages_list)" "packages.list"
    copy_to_rootfs_tmp "$(desktop_packages_remove_list)" "packages-remove.list"
    cp -a "${PROJECT_DIR}/overlay/." "${ROOTFS_DIR}/"
    copy_setup_hooks
    copy_chroot_scripts
    copy_repo_assets
}

run_chroot_script() {
    if [[ "$#" -lt 1 ]]; then
        die "run_chroot_script expects at least a script name"
    fi

    local script_name="$1"
    local guest_script_path="/tmp/${script_name}"
    shift

    chroot "${ROOTFS_DIR}" env \
        DEBIAN_FRONTEND=noninteractive \
        "$@" \
        /bin/bash -eux "${guest_script_path}"
}

cleanup_chroot_inputs() {
    rm -rf "$(rootfs_tmp_path "packages.list")" \
           "$(rootfs_tmp_path "packages-remove.list")" \
           "$(rootfs_tmp_path "setup.d")" \
           "$(rootfs_tmp_path "assets")" \
           "$(rootfs_tmp_path "run-hook-dir.sh")" \
           "$(rootfs_tmp_path "cached-curl.sh")" \
           "$(rootfs_tmp_path "install-and-customize-chroot.sh")" \
           "$(rootfs_tmp_path "trim-chroot.sh")"
}

phase_prepare() {
    phase "00 Prepare"
    require_cmd debootstrap chroot mksquashfs grub-mkrescue xorriso sha256sum

    rm -rf "${WORK_DIR}"
    mkdir -p "${ROOTFS_DIR}" "${RUNTIME_DIR}" "${ISO_STAGING_DIR}" "${OUTPUT_DIR}"

    log "Work dir: ${WORK_DIR}"
    log "Rootfs:   ${ROOTFS_DIR}"
    if [[ -n "${APT_PROXY}" ]]; then
        log "APT proxy: ${APT_PROXY}"
    else
        warn "APT proxy disabled; debootstrap and apt will download directly"
    fi
}

phase_bootstrap() {
    phase "10 Bootstrap Debian (${DEBIAN_SUITE})"

    local debootstrap_env=()
    if [[ -n "${APT_PROXY}" ]]; then
        debootstrap_env=(env http_proxy="${APT_PROXY}")
    fi
    "${debootstrap_env[@]}" debootstrap --arch="${ARCH}" --variant=minbase \
        "${DEBIAN_SUITE}" "${ROOTFS_DIR}" "${DEBIAN_MIRROR}"

    cat > "${ROOTFS_DIR}/etc/apt/sources.list" <<APT
deb ${DEBIAN_MIRROR} ${DEBIAN_SUITE} ${DEBIAN_COMPONENTS}
deb ${DEBIAN_MIRROR} ${DEBIAN_SUITE}-updates ${DEBIAN_COMPONENTS}
deb ${DEBIAN_SECURITY_MIRROR} ${DEBIAN_SUITE}-security ${DEBIAN_COMPONENTS}
APT

    cp /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf" 2>/dev/null || \
        echo 'nameserver 1.1.1.1' > "${ROOTFS_DIR}/etc/resolv.conf"

    if [[ -n "${APT_PROXY}" ]]; then
        cat > "${ROOTFS_DIR}/etc/apt/apt.conf.d/01proxy" <<APT_PROXY_EOF
Acquire::http::Proxy "${APT_PROXY}";
Acquire::https::Proxy "DIRECT";
APT_PROXY_EOF
    fi
}

phase_install_and_customize() {
    phase "20 Install + Customize"

    mount_chroot

    copy_chroot_inputs

    run_chroot_script "install-and-customize-chroot.sh" \
        DESKTOP_PROFILE="${DESKTOP_PROFILE}" \
        HOSTNAME="${HOSTNAME}" \
        LOCALE="${LOCALE}" \
        SUPPORTED_LOCALES="${SUPPORTED_LOCALES}" \
        TIMEZONE="${TIMEZONE}" \
        KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT}" \
        DEFAULT_USER="${DEFAULT_USER}" \
        DEFAULT_PASSWORD="${DEFAULT_PASSWORD}" \
        ENABLE_AUTOLOGIN="${ENABLE_AUTOLOGIN}" \
        DEFAULT_BROWSER_URL="${DEFAULT_BROWSER_URL}" \
        GNOME_INPUT_SOURCES="${GNOME_INPUT_SOURCES}" \
        MIN_RAM_MB="${MIN_RAM_MB}" \
        META_DISTRO_ID="${META_DISTRO_ID}" \
        META_DISTRO_NAME="${META_DISTRO_NAME}" \
        META_DISTRO_VERSION="${META_DISTRO_VERSION}" \
        FULL_INSTALL_URL="${FULL_INSTALL_URL}" \
        FULL_INSTALL_SHA256="${FULL_INSTALL_SHA256}" \
        UPDATE_MANIFEST_URL="${UPDATE_MANIFEST_URL}" \
        UPDATE_CHECK_ON_BOOT="${UPDATE_CHECK_ON_BOOT}" \
        RUNTIME_VERSION="${RUNTIME_VERSION}" \
        AUTH_SERVICE_URL="${AUTH_SERVICE_URL}" \
        AUTH_SERVICE_TIMEOUT="${AUTH_SERVICE_TIMEOUT}" \
        OPT_CONTEST_DIR="${OPT_CONTEST_DIR}" \
        ICP_REPORT_URL="${ICP_REPORT_URL}" \
        ICP_REPORT_TIMEOUT="${ICP_REPORT_TIMEOUT}" \
        STATS_LOG_SINCE="${STATS_LOG_SINCE}" \
        STATS_REPORT_ON_BOOT="${STATS_REPORT_ON_BOOT}" \
        STATS_REPORT_INTERVAL="${STATS_REPORT_INTERVAL}" \
        DOWNLOAD_CACHE_DIR=/tmp/download-cache \
        DOWNLOAD_CONNECTIONS="${DOWNLOAD_CONNECTIONS}"
}

phase_trim() {
    phase "30 Trim Base System"

    run_chroot_script "trim-chroot.sh" \
        META_DISTRO_NAME="${META_DISTRO_NAME}"

    cleanup_chroot_inputs
}

phase_pack_runtime() {
    phase "40 Pack Runtime Folder"

    umount_chroot

    local runtime_target="${RUNTIME_DIR}/${CONTEST_DIR}"
    local kver kernel_path initrd_path

    mkdir -p "${runtime_target}"

    kver="$(latest_kernel_version)"
    [[ -n "${kver}" ]] || die "Kernel not found in rootfs /boot"

    kernel_path="${ROOTFS_DIR}/boot/vmlinuz-${kver}"
    initrd_path="${ROOTFS_DIR}/boot/initrd.img-${kver}"

    [[ -f "${kernel_path}" ]] || die "Missing kernel file: ${kernel_path}"
    [[ -f "${initrd_path}" ]] || die "Missing initrd file: ${initrd_path}"

    cp -a "${kernel_path}" "${runtime_target}/vmlinuz"
    cp -a "${initrd_path}" "${runtime_target}/initrd.img"

    mksquashfs "${ROOTFS_DIR}" "${runtime_target}/${ROOT_SQUASH_NAME}" \
        -comp zstd -Xcompression-level 15 \
        -e boot dev proc run sys tmp \
           var/cache/apt var/lib/apt/lists var/log var/tmp

    write_runtime_grub_entry "${runtime_target}/grub-entry.cfg"
}

phase_build_iso() {
    phase "50 Build Bootable ISO"

    local runtime_target="${RUNTIME_DIR}/${CONTEST_DIR}"
    local date_stamp iso_name iso_file
    local kernel_source="${runtime_target}/vmlinuz"
    local initrd_source="${runtime_target}/initrd.img"
    local squashfs_source="${runtime_target}/${ROOT_SQUASH_NAME}"

    date_stamp="$(date +%Y%m%d)"
    iso_name="${ISO_NAME}-${date_stamp}"
    iso_file="${OUTPUT_DIR}/${iso_name}.iso"

    [[ -f "${kernel_source}" ]] || die "Missing runtime kernel: ${kernel_source}"
    [[ -f "${initrd_source}" ]] || die "Missing runtime initrd: ${initrd_source}"
    [[ -f "${squashfs_source}" ]] || die "Missing runtime squashfs: ${squashfs_source}"

    rm -rf "${ISO_STAGING_DIR}"
    mkdir -p "${ISO_STAGING_DIR}/boot/grub" "${ISO_STAGING_DIR}/${CONTEST_DIR}"

    cp -a "${kernel_source}" "${ISO_STAGING_DIR}/${CONTEST_DIR}/vmlinuz"
    cp -a "${initrd_source}" "${ISO_STAGING_DIR}/${CONTEST_DIR}/initrd.img"
    # Usa un hardlink cuando ambas rutas están en el mismo sistema de archivos
    # (por ejemplo /tmp del contenedor). Esto evita duplicar la imagen squashfs
    # de más de 3 GB y previene fallos de xorriso por falta de espacio.
    ln "${squashfs_source}" \
        "${ISO_STAGING_DIR}/${CONTEST_DIR}/${ROOT_SQUASH_NAME}" 2>/dev/null || \
        cp -a "${squashfs_source}" \
            "${ISO_STAGING_DIR}/${CONTEST_DIR}/${ROOT_SQUASH_NAME}"

    # El GRUB del ISO es el único cargador de arranque tanto para el ISO
    # como para el disco. Busca el marcador de despliegue (.contest-installed)
    # en cualquier partición local. Si lo encuentra, arranca desde disco con
    # persistencia. Si no, arranca desde el ISO y eso dispara deploy.sh para
    # copiar los archivos al disco.
    write_iso_grub_cfg "${ISO_STAGING_DIR}/boot/grub/grub.cfg"

    grub-mkrescue -o "${iso_file}" "${ISO_STAGING_DIR}" >/tmp/grub-mkrescue.log 2>&1 || {
        cat /tmp/grub-mkrescue.log >&2 || true
        die "grub-mkrescue failed"
    }

    sha256sum "${iso_file}" > "${iso_file}.sha256"

    # La carpeta runtime (squashfs + kernel + initrd) ya está embebida en el
    # ISO. Copiarla por separado a output/ consume otros 3+ GB en el volumen
    # del host. Habilita OUTPUT_RUNTIME en config/iso.conf si quieres esa copia extra.
    if [[ "${OUTPUT_RUNTIME}" == "1" ]]; then
        rm -rf "${OUTPUT_DIR}/${CONTEST_DIR}"
        cp -a "${runtime_target}" "${OUTPUT_DIR}/"
        log "Runtime:  ${OUTPUT_DIR}/${CONTEST_DIR}"
    fi

    log "ISO:      ${iso_file}"
    log "SHA256:   ${iso_file}.sha256"
}

publish_runtime_version() {
    if [[ -n "${RUNTIME_VERSION}" && "${RUNTIME_VERSION}" != "dev" ]]; then
        printf '%s\n' "${RUNTIME_VERSION}"
    else
        date -u +%Y%m%d%H%M%S
    fi
}

phase_publish_update() {
    phase "60 Publish Runtime Update"

    local runtime_target="${RUNTIME_DIR}/${CONTEST_DIR}"
    local version updates_root artifact_dir manifest_file
    local kernel_source="${runtime_target}/vmlinuz"
    local initrd_source="${runtime_target}/initrd.img"
    local squashfs_source="${runtime_target}/${ROOT_SQUASH_NAME}"
    local grub_entry_source="${runtime_target}/grub-entry.cfg"

    [[ -f "${kernel_source}" ]] || die "Missing runtime kernel: ${kernel_source}"
    [[ -f "${initrd_source}" ]] || die "Missing runtime initrd: ${initrd_source}"
    [[ -f "${squashfs_source}" ]] || die "Missing runtime squashfs: ${squashfs_source}"
    [[ -f "${grub_entry_source}" ]] || die "Missing runtime grub-entry: ${grub_entry_source}"

    updates_root="${UPDATES_DIR}"
    version="$(publish_runtime_version)"
    artifact_dir="${updates_root}/artifacts/${version}"
    manifest_file="${updates_root}/manifest.json"

    mkdir -p "${artifact_dir}"
    cp -a "${kernel_source}" "${artifact_dir}/vmlinuz"
    cp -a "${initrd_source}" "${artifact_dir}/initrd.img"
    cp -a "${squashfs_source}" "${artifact_dir}/${ROOT_SQUASH_NAME}"
    cp -a "${grub_entry_source}" "${artifact_dir}/grub-entry.cfg"

    local vmlinuz_sha initrd_sha squashfs_sha grub_entry_sha
    vmlinuz_sha="$(sha256sum "${artifact_dir}/vmlinuz" | awk '{print $1}')"
    initrd_sha="$(sha256sum "${artifact_dir}/initrd.img" | awk '{print $1}')"
    squashfs_sha="$(sha256sum "${artifact_dir}/${ROOT_SQUASH_NAME}" | awk '{print $1}')"
    grub_entry_sha="$(sha256sum "${artifact_dir}/grub-entry.cfg" | awk '{print $1}')"

    cat > "${manifest_file}" <<EOF
{
  "version": "${version}",
  "artifacts": {
    "vmlinuz": {
      "url": "artifacts/${version}/vmlinuz",
      "sha256": "${vmlinuz_sha}"
    },
    "initrd_img": {
      "url": "artifacts/${version}/initrd.img",
      "sha256": "${initrd_sha}"
    },
    "filesystem_squashfs": {
      "url": "artifacts/${version}/${ROOT_SQUASH_NAME}",
      "sha256": "${squashfs_sha}"
    },
    "grub_entry_cfg": {
      "url": "artifacts/${version}/grub-entry.cfg",
      "sha256": "${grub_entry_sha}"
    }
  }
}
EOF

    log "Update version: ${version}"
    log "Update dir:     ${artifact_dir}"
    log "Manifest:       ${manifest_file}"
}

build_runtime() {
    phase_prepare
    phase_bootstrap
    phase_install_and_customize
    phase_trim
    phase_pack_runtime
}

main() {
    build_runtime
    phase_build_iso
}

print_usage() {
    cat <<EOF
Usage: $(basename "$0") [full|runtime|publish-update|help]

Targets:
  full          Build completo (default)
  runtime       Construye hasta runtime/ + grub-entry.cfg
  publish-update Construye runtime y publica artifacts + manifest en updates/
  help          Muestra esta ayuda
EOF
}

run_build_target() {
    local target="${1:-full}"

    case "${target}" in
        full|all)
            main
            ;;
        runtime)
            build_runtime
            ;;
        publish-update|update|publish)
            build_runtime
            phase_publish_update
            ;;
        help|-h|--help)
            print_usage
            ;;
        *)
            die "Unknown build target: ${target}"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_build_target "${1:-full}"
fi
