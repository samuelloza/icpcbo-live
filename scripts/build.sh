#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_SCRIPT_DIR="${SCRIPT_DIR}/build"

# shellcheck source=./build/lib/common.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=../config/iso.conf
source "${PROJECT_DIR}/config/iso.conf"

if [[ -f "${PROJECT_DIR}/config/iso.local.conf" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_DIR}/config/iso.local.conf"
fi

resolve_output_path() {
    local path="$1"
    local fallback_name="$2"

    if [[ "${path}" == /work/* ]] && { [[ ! -d /work ]] || [[ ! -w /work ]]; }; then
        path="${PROJECT_DIR}/${fallback_name}"
    fi

    if [[ -e "${path}" ]]; then
        if [[ ! -w "${path}" ]]; then
            path="${PROJECT_DIR}/${fallback_name}-local"
        fi
    elif [[ ! -w "$(dirname "${path}")" ]]; then
        path="${PROJECT_DIR}/${fallback_name}-local"
    fi

    printf '%s\n' "${path}"
}

OUTPUT_DIR="$(resolve_output_path "${OUTPUT_DIR}" output)"
UPDATES_DIR="$(resolve_output_path "${UPDATES_DIR}" updates)"

DOWNLOAD_CACHE_DIR="${DOWNLOAD_CACHE_DIR:-/work/download-cache}"
if [[ "${DOWNLOAD_CACHE_DIR}" == /work/* ]] && { [[ ! -d /work ]] || [[ ! -w /work ]]; }; then
    DOWNLOAD_CACHE_DIR="${PROJECT_DIR}/download_cache"
fi

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
    local src="${PROJECT_DIR}/scripts/setup.d"
    local dst="$(rootfs_tmp_path "setup.d")"

    rm -rf "${dst}"
    mkdir -p "${dst}"

    [[ -d "${src}" ]] || return 0
    cp -a "${src}/." "${dst}/"
}

# Copy host-side build helper scripts into the chroot so both chroot sessions
# can use them without duplicating their definitions inline.
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

    if [[ -f "${PROJECT_DIR}/icpcbo-wallpaper.png" ]]; then
        mkdir -p "${dst}/contestant-vm/misc"
        cp "${PROJECT_DIR}/icpcbo-wallpaper.png" \
            "${dst}/contestant-vm/misc/icpcbo-wallpaper.png"
    fi
}

copy_chroot_inputs() {
    copy_to_rootfs_tmp "${PROJECT_DIR}/config/packages.list"
    copy_to_rootfs_tmp "${PROJECT_DIR}/config/packages-remove.list"
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
}

phase_bootstrap() {
    phase "10 Bootstrap Debian (${DEBIAN_SUITE})"

    local debootstrap_env=()
    if [[ -n "${APT_PROXY:-}" ]]; then
        debootstrap_env=(env http_proxy="${APT_PROXY}" https_proxy="${APT_PROXY}")
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
APT_PROXY_EOF
    fi
}

phase_install_and_customize() {
    phase "20 Install + Customize"

    mount_chroot

    copy_chroot_inputs

    run_chroot_script "install-and-customize-chroot.sh" \
        HOSTNAME="${HOSTNAME}" \
        LOCALE="${LOCALE}" \
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
        DOWNLOAD_CACHE_DIR=/work/download-cache
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

phase_generate_grub_preview() {
    phase "05 Generate GRUB Preview"

    local preview_dir="${OUTPUT_DIR}/grub-preview"
    local preview_runtime_dir="${preview_dir}/${CONTEST_DIR}"
    local preview_iso_grub_dir="${preview_dir}/boot/grub"
    local preview_iso="${OUTPUT_DIR}/${ISO_NAME}-grub-preview.iso"
    local grub_log="/tmp/grub-mkrescue-preview.log"

    require_cmd grub-mkrescue xorriso sha256sum

    rm -rf "${preview_dir}"
    rm -f "${preview_iso}" "${preview_iso}.sha256" "${grub_log}"
    mkdir -p "${preview_runtime_dir}" "${preview_iso_grub_dir}"

    write_runtime_grub_entry "${preview_runtime_dir}/grub-entry.cfg"
    write_iso_grub_cfg "${preview_iso_grub_dir}/grub.cfg"

    cat > "${preview_runtime_dir}/vmlinuz" <<'EOF'
GRUB preview placeholder kernel.
This file only exists so the preview ISO exposes the expected path.
EOF

    cat > "${preview_runtime_dir}/initrd.img" <<'EOF'
GRUB preview placeholder initrd.
This file only exists so the preview ISO exposes the expected path.
EOF

    cat > "${preview_runtime_dir}/${ROOT_SQUASH_NAME}" <<'EOF'
GRUB preview placeholder squashfs.
This file only exists so the preview ISO exposes the expected path.
EOF

    grub-mkrescue -o "${preview_iso}" "${preview_dir}" >"${grub_log}" 2>&1 || {
        cat "${grub_log}" >&2 || true
        die "grub-mkrescue failed for preview ISO"
    }

    sha256sum "${preview_iso}" > "${preview_iso}.sha256"

    log "GRUB preview runtime entry: ${preview_runtime_dir}/grub-entry.cfg"
    log "GRUB preview ISO config:   ${preview_iso_grub_dir}/grub.cfg"
    log "GRUB preview ISO:          ${preview_iso}"
    log "GRUB preview SHA256:       ${preview_iso}.sha256"
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
    # Use a hardlink when both paths are on the same filesystem (container /tmp).
    # This avoids duplicating the 3+ GB squashfs image and prevents xorriso from
    # failing with "Image size exceeds free space on media".
    ln "${squashfs_source}" \
        "${ISO_STAGING_DIR}/${CONTEST_DIR}/${ROOT_SQUASH_NAME}" 2>/dev/null || \
        cp -a "${squashfs_source}" \
            "${ISO_STAGING_DIR}/${CONTEST_DIR}/${ROOT_SQUASH_NAME}"

    # The ISO's GRUB is the single bootloader for both ISO and HDD.
    # It searches for the deploy marker (.contest-installed) on any local
    # partition. If found → boot from HDD with persistence. If not → first
    # boot from ISO, which triggers deploy.sh to copy files to the HDD.
    write_iso_grub_cfg "${ISO_STAGING_DIR}/boot/grub/grub.cfg"

    grub-mkrescue -o "${iso_file}" "${ISO_STAGING_DIR}" >/tmp/grub-mkrescue.log 2>&1 || {
        cat /tmp/grub-mkrescue.log >&2 || true
        die "grub-mkrescue failed"
    }

    sha256sum "${iso_file}" > "${iso_file}.sha256"

    # The runtime folder (squashfs + kernel + initrd) is already embedded in the
    # ISO. Copying it separately to output/ costs another 3+ GB on the host
    # volume. Set OUTPUT_RUNTIME=1 to opt in to the separate copy.
    if [[ "${OUTPUT_RUNTIME:-0}" == "1" ]]; then
        rm -rf "${OUTPUT_DIR}/${CONTEST_DIR}"
        cp -a "${runtime_target}" "${OUTPUT_DIR}/"
        log "Runtime:  ${OUTPUT_DIR}/${CONTEST_DIR}"
    fi

    log "ISO:      ${iso_file}"
    log "SHA256:   ${iso_file}.sha256"
}

publish_runtime_version() {
    if [[ -n "${RUNTIME_VERSION:-}" && "${RUNTIME_VERSION}" != "dev" ]]; then
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
Usage: $(basename "$0") [full|runtime|publish-update|grub-preview|help]

Targets:
  full          Build completo (default)
  runtime       Construye hasta runtime/ + grub-entry.cfg
  publish-update Construye runtime y publica artifacts + manifest en updates/
  grub-preview  Genera grub.cfg + grub-entry.cfg + ISO preview booteable
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
        grub-preview|grub|preview-grub)
            phase_generate_grub_preview
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
