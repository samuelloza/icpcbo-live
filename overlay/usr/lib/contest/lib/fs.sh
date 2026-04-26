#!/usr/bin/env bash

if [ -r /usr/lib/contest/lib/base.sh ]; then
    . /usr/lib/contest/lib/base.sh
else
    . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/base.sh"
fi

mount_opts_for_fstype() {
    local fstype="${1:-}"
    local mode="${2:-}"

    require_value "${fstype}" "filesystem type"
    require_value "${mode}" "mount mode"

    case "${fstype}" in
        ntfs) printf '%s,nls=utf8\n' "${mode}" ;;
        *) printf '%s\n' "${mode}" ;;
    esac
}

overlay_storage_mb_for_fstype() {
    local fstype="${1:-}"
    local overlay_img_size_mb="${2:-}"

    require_value "${fstype}" "filesystem type"
    require_value "${overlay_img_size_mb}" "overlay image size"

    case "${fstype}" in
        ext4|ext3|xfs) printf '0\n' ;;
        *) printf '%s\n' "${overlay_img_size_mb}" ;;
    esac
}

overlay_img_size_mb_for_fstype() {
    local fstype="${1:-}"
    local default_size_mb="${2:-}"

    require_value "${fstype}" "filesystem type"
    require_value "${default_size_mb}" "default overlay image size"

    case "${fstype}" in
        vfat) printf '3072\n' ;;
        *) printf '%s\n' "${default_size_mb}" ;;
    esac
}
