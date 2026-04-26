#!/usr/bin/env bash

if [ -r /usr/lib/contest/lib/base.sh ]; then
    . /usr/lib/contest/lib/base.sh
else
    . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/base.sh"
fi

read_install_marker() {
    local marker_file="${1:-}"
    local key value

    require_value "${marker_file}" "marker file"

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
            INSTALLED_DATE|INSTALL_DATE) MARKER_INSTALLED_DATE="${value}" ;;
            TARGET_DEV|TARGET_DISK|INSTALL_DEV) MARKER_TARGET_DEV="${value}" ;;
            TARGET_FSTYPE|INSTALL_FSTYPE) MARKER_TARGET_FSTYPE="${value}" ;;
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
    local contest_root="${1:-}"
    require_value "${contest_root}" "contest root"
    printf '%s/VERSION\n' "${contest_root}"
}

contest_current_dir() {
    local contest_root="${1:-}"
    require_value "${contest_root}" "contest root"
    printf '%s/current\n' "${contest_root}"
}

contest_previous_dir() {
    local contest_root="${1:-}"
    require_value "${contest_root}" "contest root"
    printf '%s/previous\n' "${contest_root}"
}

contest_staging_dir() {
    local contest_root="${1:-}"
    require_value "${contest_root}" "contest root"
    printf '%s/staging\n' "${contest_root}"
}

contest_state_dir() {
    local contest_root="${1:-}"
    require_value "${contest_root}" "contest root"
    printf '%s/state\n' "${contest_root}"
}

read_runtime_version() {
    local contest_root="${1:-}"
    local version_file

    require_value "${contest_root}" "contest root"
    version_file="$(contest_version_file "${contest_root}")"
    [ -r "${version_file}" ] || return 1
    tr -d '\n' < "${version_file}"
}

write_runtime_version() {
    local contest_root="${1:-}"
    local version="${2:-}"

    require_value "${contest_root}" "contest root"
    require_value "${version}" "runtime version"
    printf '%s\n' "${version}" > "$(contest_version_file "${contest_root}")"
}

link_runtime_files() {
    local contest_root="${1:-}"
    local current_dir

    require_value "${contest_root}" "contest root"
    current_dir="$(contest_current_dir "${contest_root}")"

    ln -sfn "current/vmlinuz" "${contest_root}/vmlinuz"
    ln -sfn "current/initrd.img" "${contest_root}/initrd.img"
    ln -sfn "current/filesystem.squashfs" "${contest_root}/filesystem.squashfs"

    if [ -f "${current_dir}/grub-entry.cfg" ]; then
        ln -sfn "current/grub-entry.cfg" "${contest_root}/grub-entry.cfg"
    fi
}
