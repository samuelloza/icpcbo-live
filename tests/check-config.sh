#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

assert_file() {
    local path="$1"

    [[ -f "${PROJECT_DIR}/${path}" ]] || fail "missing file: ${path}"
}

assert_executable() {
    local path="$1"

    [[ -x "${PROJECT_DIR}/${path}" ]] || fail "file is not executable: ${path}"
}

assert_package() {
    local pkg="$1"

    grep -qxF "${pkg}" "${PROJECT_DIR}/config/packages.list" || \
        fail "missing package in config/packages.list: ${pkg}"
}

unset ISO_NAME
unset DEBIAN_SUITE
unset META_DISTRO_ID
unset META_DISTRO_NAME
unset META_DISTRO_VERSION
unset CONTEST_DIR
unset HOSTNAME

# shellcheck source=/dev/null
source "${PROJECT_DIR}/config/iso.conf"

assert_equals "icpc-bolivia-debian" "${ISO_NAME}" "ISO_NAME"
assert_equals "trixie" "${DEBIAN_SUITE}" "DEBIAN_SUITE"
assert_equals "icpc-bolivia-debian" "${META_DISTRO_ID}" "META_DISTRO_ID"
assert_equals "ICPC Bolivia Debian" "${META_DISTRO_NAME}" "META_DISTRO_NAME"
assert_equals "13" "${META_DISTRO_VERSION}" "META_DISTRO_VERSION"
assert_equals "icpc_bo" "${CONTEST_DIR}" "CONTEST_DIR"
assert_equals "contest" "${HOSTNAME}" "HOSTNAME"

assert_file "scripts/setup.d/05-desktop-defaults.sh"
assert_file "scripts/setup.d/09-full-install-bootstrap-config.sh"
assert_file "scripts/setup.d/23-update-config.sh"
assert_file "scripts/setup.d/80-apt-policy.sh"
assert_file "scripts/setup.d/90-initramfs.sh"
assert_file "config/iso.local.conf.sample"
assert_file "overlay/etc/systemd/system/contest-deploy.service"
assert_file "overlay/etc/systemd/system/contest-full-install.service"
assert_file "overlay/etc/systemd/system/contest-overlay-provision.service"
assert_file "overlay/etc/systemd/system/contest-update.service"
assert_file "overlay/usr/lib/contest/lib/base.sh"
assert_file "overlay/usr/lib/contest/lib/fs.sh"
assert_file "overlay/usr/lib/contest/lib/runtime-layout.sh"
assert_file "overlay/usr/lib/contest/deploy.sh"
assert_file "overlay/usr/lib/contest/provision-overlay.sh"
assert_file "overlay/usr/lib/contest/update.sh"
assert_file "overlay/usr/lib/contest/rollback.sh"
assert_file "remote/full-install-bootstrap.sh"
assert_file "remote/full-install.sh"
assert_file "updates/manifest.json"
assert_file "scripts/run-hook-dir.sh"
assert_file "scripts/cached-curl.sh"
assert_file "scripts/build-menu.sh"
assert_file "scripts/build/lib/common.sh"
assert_file "scripts/build/lib/grub.sh"
assert_file "scripts/build/grub.sh"
assert_file "scripts/build/install-and-customize-chroot.sh"
assert_file "scripts/build/trim-chroot.sh"

assert_executable "overlay/usr/lib/contest/deploy.sh"
assert_executable "overlay/usr/lib/contest/provision-overlay.sh"
assert_executable "overlay/usr/lib/contest/update.sh"
assert_executable "overlay/usr/lib/contest/rollback.sh"
assert_executable "overlay/usr/lib/contest/lib/base.sh"
assert_executable "overlay/usr/lib/contest/lib/fs.sh"
assert_executable "overlay/usr/lib/contest/lib/runtime-layout.sh"
assert_executable "scripts/setup.d/09-full-install-bootstrap-config.sh"
assert_executable "scripts/setup.d/23-update-config.sh"
assert_executable "remote/full-install-bootstrap.sh"
assert_executable "remote/full-install.sh"
assert_executable "scripts/run-hook-dir.sh"
assert_executable "scripts/cached-curl.sh"
assert_executable "scripts/build-menu.sh"
assert_executable "scripts/build/lib/common.sh"
assert_executable "scripts/build/lib/grub.sh"
assert_executable "scripts/build/grub.sh"
assert_executable "scripts/build/install-and-customize-chroot.sh"
assert_executable "scripts/build/trim-chroot.sh"

if [[ -d "${PROJECT_DIR}/config/meta" ]]; then
    fail "config/meta should not exist anymore"
fi

assert_package "network-manager"
assert_package "wpasupplicant"
assert_package "wireless-regdb"
assert_package "iw"
assert_package "rfkill"
assert_package "firmware-iwlwifi"
assert_package "firmware-realtek"
assert_package "firmware-atheros"
assert_package "firmware-ath9k-htc"
assert_package "firmware-brcm80211"
assert_package "firmware-mediatek"
assert_package "firmware-misc-nonfree"
assert_package "e2fsprogs"

search_paths=()
for path in \
    "${PROJECT_DIR}/config" \
    "${PROJECT_DIR}/overlay" \
    "${PROJECT_DIR}/scripts" \
    "${PROJECT_DIR}/start.sh" \
    "${PROJECT_DIR}/README.md" \
    "${PROJECT_DIR}/Dockerfile" \
    "${PROJECT_DIR}/docker/apt-cacher-ng/Dockerfile"; do
    [[ -e "${path}" ]] && search_paths+=("${path}")
done

if command -v rg >/dev/null 2>&1; then
    if rg -n -i "nutella" "${search_paths[@]}" >/dev/null; then
        fail "old 'nutella' references still exist in runtime/build files"
    fi
else
    if grep -Rni -- "nutella" "${search_paths[@]}" >/dev/null 2>&1; then
        fail "old 'nutella' references still exist in runtime/build files"
    fi
fi

echo "PASS: config defaults, branding, Debian 13, and Wi-Fi packages look correct."
