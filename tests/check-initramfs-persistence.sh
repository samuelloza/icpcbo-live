#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "${PROJECT_DIR}/overlay/etc/initramfs-tools/scripts/local"

CONTEST_DIR="${CONTEST_DIR:-/contest}"
CONTEST_ROOT="${CONTEST_ROOT:-filesystem.squashfs}"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_exists() {
    local path="$1"
    local label="$2"
    [[ -e "${path}" ]] || fail "Expected ${label} to exist: ${path}"
}

assert_not_exists() {
    local path="$1"
    local label="$2"
    [[ ! -e "${path}" ]] || fail "Expected ${label} to be removed: ${path}"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

data_dir="${tmp_dir}/persistent-data"
meta_dir="${tmp_dir}/persistent-meta"
mkdir -p "${data_dir}/home/icpc" "${data_dir}/etc" "${meta_dir}/cache"
touch "${data_dir}/home/icpc/.bashrc" "${data_dir}/etc/issue" "${meta_dir}/cache/work"

PERSIST_DATA_DIR="${data_dir}"
PERSIST_META_DIR="${meta_dir}"
CONTEST_RESET_HOME="0"
CONTEST_RESET_PERSIST="0"
CONTEST_PERSIST_SCOPE="home"

apply_persistence_actions

assert_exists "${data_dir}/home" "persisted home"
assert_not_exists "${data_dir}/etc" "non-home persisted data"
assert_not_exists "${meta_dir}/cache" "stale persistence metadata"

mkdir -p "${data_dir}/home/icpc" "${data_dir}/var/tmp" "${meta_dir}/pending"
touch "${data_dir}/home/icpc/.profile" "${data_dir}/var/tmp/file" "${meta_dir}/pending/work"

CONTEST_RESET_HOME="1"
CONTEST_RESET_PERSIST="0"
CONTEST_PERSIST_SCOPE="home"

apply_persistence_actions

assert_not_exists "${data_dir}/home" "persisted home after reset_home"
assert_not_exists "${data_dir}/var" "non-home data after reset_home"
assert_not_exists "${meta_dir}/pending" "metadata after reset_home"

mkdir -p "${data_dir}/home/icpc" "${data_dir}/opt" "${meta_dir}/pending"
touch "${data_dir}/home/icpc/.zshrc" "${data_dir}/opt/tool" "${meta_dir}/pending/work"

CONTEST_RESET_HOME="0"
CONTEST_RESET_PERSIST="1"
CONTEST_PERSIST_SCOPE="home"

apply_persistence_actions

assert_not_exists "${data_dir}/home" "persisted home after reset_persist"
assert_not_exists "${data_dir}/opt" "persisted files after reset_persist"
assert_not_exists "${meta_dir}/pending" "metadata after reset_persist"

install_mount="${tmp_dir}/install-mount"
mkdir -p "${install_mount}${CONTEST_DIR}"
touch \
    "${install_mount}${CONTEST_DIR}/vmlinuz" \
    "${install_mount}${CONTEST_DIR}/initrd.img" \
    "${install_mount}${CONTEST_DIR}/${CONTEST_ROOT}"

portable_install_present_at "${install_mount}" || fail "Expected portable install marker set to be detected"
remove_portable_install_at "${install_mount}" || fail "Expected portable install to be removable"
assert_not_exists "${install_mount}${CONTEST_DIR}" "portable install directory after cleanup"

fakebin="${tmp_dir}/fakebin"
mkdir -p "${fakebin}"
cat > "${fakebin}/mke2fs" <<'EOF_MKE2FS'
#!/bin/sh
for arg in "$@"; do
    if [ "${arg}" = "-t" ]; then
        exit 1
    fi
done
printf '%s\n' "$*" > "${FORMAT_EXT4_LOG:?}"
exit 0
EOF_MKE2FS
chmod +x "${fakebin}/mke2fs"

FORMAT_EXT4_LOG="${tmp_dir}/format-ext4.log"
export FORMAT_EXT4_LOG
CONTEST_EXT4_FORMATTER="${fakebin}/mke2fs" format_ext4_overlay_image "${tmp_dir}/overlay.img"
assert_exists "${FORMAT_EXT4_LOG}" "mke2fs invocation log"
grep -q -- '-F -L contest-overlay' "${FORMAT_EXT4_LOG}" || fail "Expected format_ext4_overlay_image to use BusyBox-compatible mke2fs arguments"

privatebin="${tmp_dir}/privatebin"
mkdir -p "${privatebin}"
cp "${fakebin}/mke2fs" "${privatebin}/mke2fs"
chmod +x "${privatebin}/mke2fs"
FORMAT_EXT4_LOG="${tmp_dir}/format-ext4-private.log"
export FORMAT_EXT4_LOG
if ! CONTEST_EXT4_FORMATTER="${privatebin}/mke2fs" format_ext4_overlay_image "${tmp_dir}/overlay-private.img"; then
    fail "Expected private contest formatter path to work"
fi
assert_exists "${FORMAT_EXT4_LOG}" "private mke2fs invocation log"

unset CONTEST_TEST_REBOOT_REASON
unset CONTEST_TEST_REBOOT_DELAY
CONTEST_TEST_NO_REBOOT="1"
install_complete_message_and_reboot "/dev/test0"
assert_exists "/dev/null" "sanity placeholder"
[[ "${CONTEST_TEST_REBOOT_REASON:-}" = "delayed" ]] || fail "Expected install_complete_message_and_reboot to request delayed reboot"
[[ "${CONTEST_TEST_REBOOT_DELAY:-}" = "5" ]] || fail "Expected install_complete_message_and_reboot to use a 5 second reboot delay"
unset CONTEST_TEST_NO_REBOOT

unset CONTEST_TEST_STOP_REASON
CONTEST_TEST_NO_REBOOT="1"
stop_for_debug "fatal-test"
[[ "${CONTEST_TEST_STOP_REASON:-}" = "fatal-test" ]] || fail "Expected fatal boot errors to stop for debugging"
unset CONTEST_TEST_STOP_REASON

cleanup_message_and_stop "ERROR DE PRUEBA" "detalle"
[[ "${CONTEST_TEST_STOP_REASON:-}" = "ERROR DE PRUEBA" ]] || fail "Expected displayed boot errors to stop without rebooting"
unset CONTEST_TEST_STOP_REASON
unset CONTEST_TEST_NO_REBOOT

keybin="${tmp_dir}/keybin"
mkdir -p "${keybin}"
cat > "${keybin}/stty" <<'EOF_STTY'
#!/bin/sh
if [ "${1:-}" = "-g" ]; then
    echo sane
fi
exit 0
EOF_STTY
cat > "${keybin}/dd" <<'EOF_DD'
#!/bin/sh
cat >/dev/null
exit 0
EOF_DD
chmod +x "${keybin}/stty" "${keybin}/dd"

printf 'x' > "${tmp_dir}/console-input"
PATH="${keybin}:${PATH}"
CONTEST_TEST_NO_REBOOT="1"
CONTEST_TEST_KEY_DEV="${tmp_dir}/console-input"
wait_for_reboot_key
[[ "${CONTEST_TEST_REBOOT_REASON:-}" = "key" ]] || fail "Expected wait_for_reboot_key to reboot after a single key"
unset CONTEST_TEST_REBOOT_REASON
unset CONTEST_TEST_KEY_DEV
unset CONTEST_TEST_NO_REBOOT

FOUND_FSTYPE="iso9660"
CONTEST_INSTALL_MODE="live"
CONTEST_REINSTALL="0"
auto_install_to_disk

_scan_install_partitions() {
    local records="$2"
    cat > "${records}" <<'EOF_PARTITIONS'
/dev/sda1|ntfs3|524288000|419430400|BLOQUEADA/SOLO LECTURA
/dev/sda2|ext4|104857600|52428800|APTA
/dev/sdb1|xfs|209715200|83886080|APTA
/dev/sdc1|ext4|8388608|4194304|SIN ESPACIO
EOF_PARTITIONS
}

partition_summary="${tmp_dir}/partition-summary"
CONTEST_INSTALL_RECORDS="${tmp_dir}/partition-records"
INSTALL_ERROR=""
_find_install_target /dev/iso 2>"${partition_summary}" || fail "Expected an eligible install target"
[[ "${INSTALL_DEV}" = "/dev/sdb1" ]] || fail "Expected the partition with the most free space, got ${INSTALL_DEV}"
[[ "${INSTALL_FSTYPE}" = "xfs" ]] || fail "Expected selected filesystem xfs, got ${INSTALL_FSTYPE}"
grep -q '/dev/sda1.*BLOQUEADA/SOLO LECTURA' "${partition_summary}" || fail "Expected locked partition in summary"
grep -q '/dev/sda2.*APTA' "${partition_summary}" || fail "Expected first eligible partition in summary"
grep -q '/dev/sdb1.*APTA' "${partition_summary}" || fail "Expected selected partition in summary"
grep -q '/dev/sdc1.*SIN ESPACIO' "${partition_summary}" || fail "Expected undersized partition in summary"

echo "PASS: initramfs persistence actions keep only home, clear home, and wipe persistence as expected."
