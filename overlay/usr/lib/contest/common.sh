#!/usr/bin/env bash

normalize_contest_dir() {
    local dir="${1:-/contest}"

    case "${dir}" in
        /*) printf '%s\n' "${dir}" ;;
        *) printf '/%s\n' "${dir}" ;;
    esac
}

cmdline_param() {
    local key="${1:?missing kernel cmdline key}"
    local cmdline_file="${CMDLINE_FILE:-/proc/cmdline}"

    tr ' ' '\n' < "${cmdline_file}" | grep -m1 "^${key}=" | cut -d= -f2- || true
}

mount_opts_for_fstype() {
    local fstype="${1:?missing filesystem type}"
    local mode="${2:?missing mount mode}"

    case "${fstype}" in
        ntfs) printf '%s,nls=utf8\n' "${mode}" ;;
        ntfs3) printf '%s\n' "${mode}" ;;
        *) printf '%s\n' "${mode}" ;;
    esac
}

overlay_storage_mb_for_fstype() {
    local fstype="${1:?missing filesystem type}"
    local overlay_img_size_mb="${2:?missing overlay image size}"

    case "${fstype}" in
        ext4|ext3|xfs) printf '0\n' ;;
        *) printf '%s\n' "${overlay_img_size_mb}" ;;
    esac
}

overlay_img_size_mb_for_fstype() {
    local fstype="${1:?missing filesystem type}"
    local default_size_mb="${2:?missing default overlay image size}"

    case "${fstype}" in
        vfat) printf '3072\n' ;;
        *) printf '%s\n' "${default_size_mb}" ;;
    esac
}

read_install_marker() {
    local marker_file="${1:?missing marker file}"
    local key value

    MARKER_INSTALLED_DATE=""
    MARKER_INSTALL_TYPE=""
    MARKER_TARGET_DEV=""
    MARKER_TARGET_FSTYPE=""
    MARKER_OVERLAY_IMG_CREATED=""
    MARKER_CONTEST_DIR=""
    MARKER_CONTEST_ROOT=""
    MARKER_EFI_BOOT_NUM=""
    MARKER_ROOT_PART=""
    MARKER_ROOT_UUID=""

    while IFS='=' read -r key value; do
        case "${key}" in
            INSTALL_TYPE) MARKER_INSTALL_TYPE="${value}" ;;
            INSTALLED_DATE) MARKER_INSTALLED_DATE="${value}" ;;
            INSTALL_DATE) MARKER_INSTALLED_DATE="${value}" ;;
            TARGET_DEV) MARKER_TARGET_DEV="${value}" ;;
            TARGET_DISK) MARKER_TARGET_DEV="${value}" ;;
            TARGET_FSTYPE) MARKER_TARGET_FSTYPE="${value}" ;;
            OVERLAY_IMG_CREATED) MARKER_OVERLAY_IMG_CREATED="${value}" ;;
            CONTEST_DIR) MARKER_CONTEST_DIR="${value}" ;;
            CONTEST_ROOT) MARKER_CONTEST_ROOT="${value}" ;;
            EFI_BOOT_NUM) MARKER_EFI_BOOT_NUM="${value}" ;;
            ROOT_PART) MARKER_ROOT_PART="${value}" ;;
            ROOT_UUID) MARKER_ROOT_UUID="${value}" ;;
            *) ;;
        esac
    done < "${marker_file}"
}

contest_version_file() {
    local contest_root="${1:?missing contest root}"
    printf '%s/VERSION\n' "${contest_root}"
}

contest_current_dir() {
    local contest_root="${1:?missing contest root}"
    printf '%s/current\n' "${contest_root}"
}

contest_previous_dir() {
    local contest_root="${1:?missing contest root}"
    printf '%s/previous\n' "${contest_root}"
}

contest_staging_dir() {
    local contest_root="${1:?missing contest root}"
    printf '%s/staging\n' "${contest_root}"
}

contest_state_dir() {
    local contest_root="${1:?missing contest root}"
    printf '%s/state\n' "${contest_root}"
}

read_runtime_version() {
    local contest_root="${1:?missing contest root}"
    local version_file
    version_file="$(contest_version_file "${contest_root}")"

    [ -r "${version_file}" ] || return 1
    tr -d '\n' < "${version_file}"
}

write_runtime_version() {
    local contest_root="${1:?missing contest root}"
    local version="${2:?missing runtime version}"
    printf '%s\n' "${version}" > "$(contest_version_file "${contest_root}")"
}

link_runtime_files() {
    local contest_root="${1:?missing contest root}"
    local current_dir
    current_dir="$(contest_current_dir "${contest_root}")"

    ln -sfn "current/vmlinuz" "${contest_root}/vmlinuz"
    ln -sfn "current/initrd.img" "${contest_root}/initrd.img"
    ln -sfn "current/filesystem.squashfs" "${contest_root}/filesystem.squashfs"

    if [ -f "${current_dir}/grub-entry.cfg" ]; then
        ln -sfn "current/grub-entry.cfg" "${contest_root}/grub-entry.cfg"
    fi
}
