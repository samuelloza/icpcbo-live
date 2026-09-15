#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_SCRIPT_DIR="${SCRIPT_DIR}/build"

# shellcheck source=./build/lib/common.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=../config/iso.conf
source "${PROJECT_DIR}/config/iso.conf"

ISO_FLAVOR="${ISO_FLAVOR:-seed}"

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
BASE_CACHE_DIR="$(resolve_project_path "${BASE_CACHE_DIR:-${PROJECT_TMP_DIR}/base-cache}" "${PROJECT_TMP_DIR}/base-cache")"

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
    copy_to_rootfs_tmp "${BUILD_SCRIPT_DIR}/install-packages-chroot.sh"
    copy_to_rootfs_tmp "${BUILD_SCRIPT_DIR}/install-and-customize-chroot.sh"
    copy_to_rootfs_tmp "${BUILD_SCRIPT_DIR}/trim-chroot.sh"
}

# Clave del caché del rootfs base: cambia solo si cambia la suite/mirror/arch,
# la lista de paquetes del perfil, o el script que los instala.
base_cache_key() {
    {
        printf '%s\n' "${ARCH}" "${DEBIAN_SUITE}" "${DEBIAN_MIRROR}" \
            "${DEBIAN_SECURITY_MIRROR}" "${DEBIAN_COMPONENTS}"
        cat "$(desktop_packages_list)"
        cat "${BUILD_SCRIPT_DIR}/install-packages-chroot.sh"
    } | sha256sum | cut -c1-16
}

base_cache_file() {
    printf '%s/base-%s-%s.tar.zst\n' \
        "${BASE_CACHE_DIR}" "${DESKTOP_PROFILE}" "$(base_cache_key)"
}

write_chroot_apt_and_dns() {
    cat > "${ROOTFS_DIR}/etc/apt/sources.list" <<APT
deb ${DEBIAN_MIRROR} ${DEBIAN_SUITE} ${DEBIAN_COMPONENTS}
deb ${DEBIAN_MIRROR} ${DEBIAN_SUITE}-updates ${DEBIAN_COMPONENTS}
deb ${DEBIAN_SECURITY_MIRROR} ${DEBIAN_SUITE}-security ${DEBIAN_COMPONENTS}
APT
    cp /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf" 2>/dev/null || \
        echo 'nameserver 1.1.1.1' > "${ROOTFS_DIR}/etc/resolv.conf"

    rm -f "${ROOTFS_DIR}/etc/apt/apt.conf.d/01proxy"
    if [[ -n "${APT_PROXY}" ]]; then
        cat > "${ROOTFS_DIR}/etc/apt/apt.conf.d/01proxy" <<APT_PROXY_EOF
Acquire::http::Proxy "${APT_PROXY}";
Acquire::https::Proxy "DIRECT";
APT_PROXY_EOF
    fi
}

save_base_cache() {
    local cache; cache="$(base_cache_file)"
    mkdir -p "${BASE_CACHE_DIR}"
    log "Guardando caché del rootfs base: ${cache}"
    # --one-file-system deja fuera /dev /proc /sys /run y los bind mounts
    # (apt-cache, download-cache). Se excluye /tmp (efímero).
    tar --one-file-system --numeric-owner --xattrs --acls \
        --exclude='./tmp/*' -I 'zstd -T0 -3' \
        -C "${ROOTFS_DIR}" -cf "${cache}.partial" . || {
        rm -f "${cache}.partial"
        warn "No se pudo guardar el caché base (se sigue sin él)"
        return 0
    }
    mv -f "${cache}.partial" "${cache}"
    # retención: 3 tarballs más nuevos por perfil
    ls -1t "${BASE_CACHE_DIR}"/base-"${DESKTOP_PROFILE}"-*.tar.zst 2>/dev/null \
        | tail -n +4 | xargs -r rm -f
}

restore_base_cache() {
    local cache; cache="$(base_cache_file)"
    [[ "${BUILD_NO_BASE_CACHE:-0}" == "1" ]] && return 1
    [[ -f "${cache}" ]] || return 1
    log "Caché del rootfs base ENCONTRADO: ${cache}"
    log "  (BUILD_NO_BASE_CACHE=1 para ignorarlo y reconstruir)"
    mkdir -p "${ROOTFS_DIR}"
    tar --numeric-owner --xattrs --acls -I 'zstd -d -T0' \
        -C "${ROOTFS_DIR}" -xf "${cache}" || {
        warn "Caché base corrupto; se reconstruye"
        rm -rf "${ROOTFS_DIR:?}"/* "${ROOTFS_DIR:?}"/.[!.]* 2>/dev/null || true
        return 1
    }
    return 0
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

stage_security_file() {
    local source_path="$1"
    local destination_name="$2"
    local mode="$3"
    local destination_dir

    [[ -n "${source_path}" ]] || return 0
    [[ "${source_path}" == /* ]] || die "Security file must use an absolute path: ${source_path}"
    [[ -f "${source_path}" ]] || die "Security file does not exist: ${source_path}"
    if [[ "${mode}" == "0600" && "$(stat -c %a "${source_path}")" != "600" ]]; then
        die "Private security file must have mode 0600: ${source_path}"
    fi

    destination_dir="$(rootfs_tmp_path "contest-security")"
    install -d -m 0700 "${destination_dir}"
    install -m "${mode}" "${source_path}" "${destination_dir}/${destination_name}"
}

stage_security_files() {
    rm -rf "$(rootfs_tmp_path "contest-security")"
    stage_security_file "${UPDATE_SIGNATURE_PUBKEY_FILE}" update-signing.pub 0644
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
           "$(rootfs_tmp_path "contest-security")" \
           "$(rootfs_tmp_path "run-hook-dir.sh")" \
           "$(rootfs_tmp_path "cached-curl.sh")" \
           "$(rootfs_tmp_path "install-and-customize-chroot.sh")" \
           "$(rootfs_tmp_path "trim-chroot.sh")"
}

phase_prepare() {
    phase "00 Prepare"
    require_cmd debootstrap chroot mksquashfs grub-mkrescue xorriso sha256sum tar zstd python3

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

    if restore_base_cache; then
        write_chroot_apt_and_dns
        log "Rootfs base restaurado del caché — se omiten debootstrap + apt install"
        return 0
    fi

    log "Caché del rootfs base: MISS — debootstrap + apt install (se guardará al terminar)"

    local debootstrap_env=()
    if [[ -n "${APT_PROXY}" ]]; then
        debootstrap_env=(env http_proxy="${APT_PROXY}")
    fi
    "${debootstrap_env[@]}" debootstrap --arch="${ARCH}" --variant=minbase \
        "${DEBIAN_SUITE}" "${ROOTFS_DIR}" "${DEBIAN_MIRROR}"

    write_chroot_apt_and_dns

    # Instala los paquetes del perfil en su propia pasada de chroot para poder
    # cachear el resultado antes de aplicar los hooks.
    mount_chroot
    copy_to_rootfs_tmp "$(desktop_packages_list)" "packages.list"
    copy_to_rootfs_tmp "${BUILD_SCRIPT_DIR}/install-packages-chroot.sh"
    run_chroot_script "install-packages-chroot.sh"
    rm -f "$(rootfs_tmp_path "packages.list")" \
          "$(rootfs_tmp_path "install-packages-chroot.sh")"
    umount_chroot

    [[ "${BUILD_NO_BASE_CACHE:-0}" == "1" ]] || save_base_cache
}

phase_install_and_customize() {
    phase "20 Install + Customize"

    mount_chroot

    copy_chroot_inputs
    stage_security_files

    run_chroot_script "install-and-customize-chroot.sh" \
        DESKTOP_PROFILE="${DESKTOP_PROFILE}" \
        HOSTNAME="${HOSTNAME}" \
        LOCALE="${LOCALE}" \
        SUPPORTED_LOCALES="${SUPPORTED_LOCALES}" \
        TIMEZONE="${TIMEZONE}" \
        KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT}" \
        DEFAULT_USER="${DEFAULT_USER}" \
        DEFAULT_PASSWORD="${DEFAULT_PASSWORD}" \
        ROOT_PASSWORD="${ROOT_PASSWORD:-}" \
        DEBUG_SUDO="${DEBUG_SUDO:-false}" \
        ENABLE_AUTOLOGIN="${ENABLE_AUTOLOGIN}" \
        DEFAULT_BROWSER_URL="${DEFAULT_BROWSER_URL}" \
        GNOME_INPUT_SOURCES="${GNOME_INPUT_SOURCES}" \
        MIN_RAM_MB="${MIN_RAM_MB}" \
        META_DISTRO_ID="${META_DISTRO_ID}" \
        META_DISTRO_NAME="${META_DISTRO_NAME}" \
        META_DISTRO_VERSION="${META_DISTRO_VERSION}" \
        REGION_ID="${REGION_ID:-}" \
        REGION_NAME="${REGION_NAME:-}" \
        UPDATE_SIGNATURE_PUBKEY="${UPDATE_SIGNATURE_PUBKEY}" \
        UPDATE_SIGNATURE_PUBKEY_SOURCE="/tmp/contest-security/update-signing.pub" \
        TEAM_ID_REQUIRED="${TEAM_ID_REQUIRED}" \
        AUTH_SERVICE_URL="${AUTH_SERVICE_URL}" \
        AUTH_SERVICE_TIMEOUT="${AUTH_SERVICE_TIMEOUT}" \
        OPT_CONTEST_DIR="${OPT_CONTEST_DIR}" \
        PULSO_RELEASE_URL="${PULSO_RELEASE_URL:-}" \
        PULSO_PUSHGATEWAY_URL="${PULSO_PUSHGATEWAY_URL:-}" \
        PULSO_JOB="${PULSO_JOB:-pulso}" \
        NET_LOCKDOWN="${NET_LOCKDOWN:-true}" \
        NET_DNS_SERVERS="${NET_DNS_SERVERS:-}" \
        NET_NTP_SERVERS="${NET_NTP_SERVERS:-}" \
        NET_ALLOW_HOSTS="${NET_ALLOW_HOSTS:-}" \
        USB_STORAGE_DEFAULT="${USB_STORAGE_DEFAULT:-blocked}" \
        CONTROL_SERVICE_URL="${CONTROL_SERVICE_URL:-}" \
        CONTROL_TIMEOUT="${CONTROL_TIMEOUT:-20}" \
        CONTROL_LONGPOLL_WAIT="${CONTROL_LONGPOLL_WAIT:-25}" \
        CONTROL_STATUS_EVERY="${CONTROL_STATUS_EVERY:-1}" \
        CONTROL_JOURNAL_EVERY="${CONTROL_JOURNAL_EVERY:-20}" \
        GROUP_ID="${GROUP_ID:-}" \
        ENROLL_TOKEN="${ENROLL_TOKEN:-}" \
        ALLOW_VM="${ALLOW_VM:-false}" \
        LOCKSCREEN_PASSWORD="${LOCKSCREEN_PASSWORD:-}" \
        DOWNLOAD_CACHE_DIR=/tmp/download-cache \
        DOWNLOAD_CONNECTIONS="${DOWNLOAD_CONNECTIONS}"

    [[ -z "${PULSO_PUSHGATEWAY_URL:-}" || -x "${ROOTFS_DIR}/usr/local/bin/pulso" ]] || \
        die "Pulso quedó habilitado pero falta ${ROOTFS_DIR}/usr/local/bin/pulso"
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

    # El árbol extraído (~10 GB) ya no se usa: el squashfs está empaquetado y las
    # fases siguientes (ISO) solo leen RUNTIME_DIR.
    # Liberarlo aquí evita quedarse sin espacio al escribir el ISO.
    if [[ "${KEEP_ROOTFS:-0}" != "1" ]]; then
        rm -rf "${ROOTFS_DIR}"
        log "Rootfs extraído eliminado (KEEP_ROOTFS=1 para conservarlo)"
    fi
}

phase_build_iso() {
    phase "50 Build Bootable ISO"

    local runtime_target="${RUNTIME_DIR}/${CONTEST_DIR}"
    local iso_name iso_file
    local kernel_source="${runtime_target}/vmlinuz"
    local initrd_source="${runtime_target}/initrd.img"
    local squashfs_source="${runtime_target}/${ROOT_SQUASH_NAME}"
    local grub_entry_source="${runtime_target}/grub-entry.cfg"

    case "${ISO_FLAVOR}" in
        seed) ;;
        *) die "ISO flavor desconocido: ${ISO_FLAVOR}" ;;
    esac

    iso_name="${REGION_ID:+${REGION_ID}-}20260901222621"
    iso_file="${OUTPUT_DIR}/${iso_name}.iso"

    [[ -f "${kernel_source}" ]] || die "Missing runtime kernel: ${kernel_source}"
    [[ -f "${initrd_source}" ]] || die "Missing runtime initrd: ${initrd_source}"
    [[ -f "${squashfs_source}" ]] || die "Missing runtime squashfs: ${squashfs_source}"
    [[ -f "${grub_entry_source}" ]] || die "Missing runtime grub entry: ${grub_entry_source}"

    rm -rf "${ISO_STAGING_DIR}"
    mkdir -p "${ISO_STAGING_DIR}/boot/grub" "${ISO_STAGING_DIR}/${CONTEST_DIR}"

    cp -a "${kernel_source}" "${ISO_STAGING_DIR}/${CONTEST_DIR}/vmlinuz"
    cp -a "${initrd_source}" "${ISO_STAGING_DIR}/${CONTEST_DIR}/initrd.img"
    cp -a "${grub_entry_source}" "${ISO_STAGING_DIR}/${CONTEST_DIR}/grub-entry.cfg"

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
    # persistencia. Si no, arranca desde el ISO y el initramfs copia los
    # archivos al disco.
    write_iso_grub_cfg "${ISO_STAGING_DIR}/boot/grub/grub.cfg"

    grub-mkrescue -o "${iso_file}" "${ISO_STAGING_DIR}" >/tmp/grub-mkrescue.log 2>&1 || {
        cat /tmp/grub-mkrescue.log >&2 || true
        die "grub-mkrescue failed"
    }

    # El manifiesto debe ser portable entre el contenedor de build y el host:
    # solo debe contener el nombre del ISO, no la ruta `/work/...` del builder.
    (cd "${OUTPUT_DIR}" && sha256sum "${iso_name}.iso") > "${iso_file}.sha256"

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
Usage: $(basename "$0") [seed|full|runtime|help]

Targets:
  seed          ISO completa para el primer seed (default)
  full          Alias de seed
  runtime       Construye hasta runtime/ + grub-entry.cfg
  help          Muestra esta ayuda
EOF
}

run_build_target() {
    local target="${1:-full}"

    case "${target}" in
        seed|full|all)
            ISO_FLAVOR=seed main
            ;;
        deploy)
            die "El build principal solo genera la ISO completa"
            ;;
        runtime)
            build_runtime
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
    target="${1:-full}"
    run_build_target "${target}"
fi
