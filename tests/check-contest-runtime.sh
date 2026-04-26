#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "${PROJECT_DIR}/overlay/usr/lib/contest/lib/base.sh"
# shellcheck source=/dev/null
source "${PROJECT_DIR}/overlay/usr/lib/contest/lib/fs.sh"
# shellcheck source=/dev/null
source "${PROJECT_DIR}/overlay/usr/lib/contest/lib/runtime-layout.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local label="$3"

    if [[ "${actual}" != "${expected}" ]]; then
        fail "${label}: expected '${expected}', got '${actual}'"
    fi
}

assert_unset() {
    local var_name="$1"

    [[ ! -v "${var_name}" ]] || fail "variable should not be set: ${var_name}"
}

assert_equals "/contest" "$(normalize_contest_dir contest)" "normalize_contest_dir relative"
assert_equals "/contest" "$(normalize_contest_dir /contest)" "normalize_contest_dir absolute"

assert_equals "ro,nls=utf8" "$(mount_opts_for_fstype ntfs ro)" "mount_opts_for_fstype ntfs ro"
assert_equals "rw" "$(mount_opts_for_fstype ntfs3 rw)" "mount_opts_for_fstype ntfs3 rw"
assert_equals "rw" "$(mount_opts_for_fstype ext4 rw)" "mount_opts_for_fstype ext4 rw"

assert_equals "0" "$(overlay_storage_mb_for_fstype ext4 4096)" "overlay_storage_mb_for_fstype ext4"
assert_equals "4096" "$(overlay_storage_mb_for_fstype ntfs 4096)" "overlay_storage_mb_for_fstype ntfs"
assert_equals "4096" "$(overlay_storage_mb_for_fstype exfat 4096)" "overlay_storage_mb_for_fstype exfat"
assert_equals "3072" "$(overlay_img_size_mb_for_fstype vfat 4096)" "overlay_img_size_mb_for_fstype vfat"
assert_equals "4096" "$(overlay_img_size_mb_for_fstype ntfs 4096)" "overlay_img_size_mb_for_fstype ntfs"

marker_contents="$(
    cat <<'EOF'
INSTALLED_DATE=2026-04-02T00:00:00Z
TARGET_DEV=/dev/sda1
TARGET_FSTYPE=ext4
OVERLAY_IMG_CREATED=0
CONTEST_DIR=/contest
CONTEST_ROOT=filesystem.squashfs
HACKED=\$(printf hacked)
EOF
)"

read_install_marker <(printf '%s\n' "${marker_contents}")

assert_equals "2026-04-02T00:00:00Z" "${MARKER_INSTALLED_DATE}" "read_install_marker installed date"
assert_equals "/dev/sda1" "${MARKER_TARGET_DEV}" "read_install_marker target dev"
assert_equals "ext4" "${MARKER_TARGET_FSTYPE}" "read_install_marker target fstype"
assert_equals "0" "${MARKER_OVERLAY_IMG_CREATED}" "read_install_marker overlay flag"
assert_equals "/contest" "${MARKER_CONTEST_DIR}" "read_install_marker contest dir"
assert_equals "filesystem.squashfs" "${MARKER_CONTEST_ROOT}" "read_install_marker contest root"
assert_unset HACKED

echo "PASS: contest runtime helpers parse markers safely and compute filesystem policy correctly."
