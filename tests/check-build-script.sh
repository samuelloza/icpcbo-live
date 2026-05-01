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
        printf 'Expected %s:\n%s\n' "${label}" "${expected}" >&2
        printf 'Actual %s:\n%s\n' "${label}" "${actual}" >&2
        fail "${label} does not match expected content"
    fi
}

assert_file() {
    local path="$1"
    [[ -f "${path}" ]] || fail "missing file: ${path}"
}

assert_not_file() {
    local path="$1"
    [[ ! -f "${path}" ]] || fail "file should not exist: ${path}"
}

assert_executable() {
    local path="$1"
    [[ -x "${path}" ]] || fail "file is not executable: ${path}"
}

# shellcheck source=/dev/null
source "${PROJECT_DIR}/scripts/build.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

ROOTFS_DIR="${tmp_dir}/rootfs"
mkdir -p "${ROOTFS_DIR}/tmp"

copy_setup_hooks
assert_file "${ROOTFS_DIR}/tmp/setup.d/01-base-cleanup.sh"
assert_file "${ROOTFS_DIR}/tmp/setup.d/09-full-install-bootstrap-config.sh"
assert_file "${ROOTFS_DIR}/tmp/setup.d/12-install-vscode.sh"
assert_file "${ROOTFS_DIR}/tmp/setup.d/89-prune-locales.sh"
assert_file "${ROOTFS_DIR}/tmp/setup.d/80-apt-policy.sh"
assert_file "${ROOTFS_DIR}/tmp/setup.d/90-initramfs.sh"

copy_chroot_scripts
assert_file "${ROOTFS_DIR}/tmp/run-hook-dir.sh"
assert_file "${ROOTFS_DIR}/tmp/cached-curl.sh"
assert_file "${ROOTFS_DIR}/tmp/install-and-customize-chroot.sh"
assert_file "${ROOTFS_DIR}/tmp/trim-chroot.sh"
assert_executable "${ROOTFS_DIR}/tmp/run-hook-dir.sh"
assert_executable "${ROOTFS_DIR}/tmp/cached-curl.sh"
assert_executable "${ROOTFS_DIR}/tmp/install-and-customize-chroot.sh"
assert_executable "${ROOTFS_DIR}/tmp/trim-chroot.sh"

if grep -Eq '^[[:space:]]*apt-get[[:space:]]+clean' "${PROJECT_DIR}/scripts/build/trim-chroot.sh"; then
    fail "trim-chroot.sh must not clean the host-mounted apt cache"
fi

grep -q '! -name download-cache' "${PROJECT_DIR}/scripts/build/trim-chroot.sh" || \
    fail "trim-chroot.sh must preserve the host-mounted download cache"

OUTPUT_DIR="${tmp_dir}/output"
stub_bin_dir="${tmp_dir}/bin"
grub_mkrescue_calls="${tmp_dir}/grub-mkrescue-calls.txt"
mkdir -p "${stub_bin_dir}"
PATH="${stub_bin_dir}:${PATH}"

cat > "${stub_bin_dir}/xorriso" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "${stub_bin_dir}/grub-mkrescue" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "${tmp_dir}/grub-mkrescue-calls.txt"
out_file=""
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        -o)
            out_file="\$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
: > "\${out_file}"
EOF

chmod +x "${stub_bin_dir}/xorriso" "${stub_bin_dir}/grub-mkrescue"

phase_generate_grub_preview
assert_file "${OUTPUT_DIR}/grub-preview/${CONTEST_DIR}/grub-entry.cfg"
assert_file "${OUTPUT_DIR}/grub-preview/boot/grub/grub.cfg"
assert_file "${OUTPUT_DIR}/${ISO_NAME}-grub-preview.iso"
assert_file "${OUTPUT_DIR}/${ISO_NAME}-grub-preview.iso.sha256"
assert_file "${OUTPUT_DIR}/grub-preview/${CONTEST_DIR}/vmlinuz"
assert_file "${OUTPUT_DIR}/grub-preview/${CONTEST_DIR}/initrd.img"
assert_file "${OUTPUT_DIR}/grub-preview/${CONTEST_DIR}/${ROOT_SQUASH_NAME}"
assert_not_file "${OUTPUT_DIR}/grub-preview/${CONTEST_DIR}/.contest-installed"

assert_equals "$(cat <<EOF
-o
${OUTPUT_DIR}/${ISO_NAME}-grub-preview.iso
${OUTPUT_DIR}/grub-preview
EOF
)" "$(cat "${grub_mkrescue_calls}")" "phase_generate_grub_preview grub-mkrescue argv"

captured_chroot_args="${tmp_dir}/chroot-args.txt"
chroot() {
    printf '%s\n' "$@" > "${captured_chroot_args}"
}

run_chroot_script "install-and-customize-chroot.sh" HOSTNAME=contest DOWNLOAD_CACHE_DIR=/tmp/download-cache

assert_equals "$(cat <<EOF
${ROOTFS_DIR}
env
DEBIAN_FRONTEND=noninteractive
HOSTNAME=contest
DOWNLOAD_CACHE_DIR=/tmp/download-cache
/bin/bash
-eux
/tmp/install-and-customize-chroot.sh
EOF
)" "$(cat "${captured_chroot_args}")" "run_chroot_script argv"

phase_log="${tmp_dir}/phase-order.log"
target_log="${tmp_dir}/target-order.log"

phase_prepare() { echo "phase_prepare" >> "${phase_log}"; }
phase_bootstrap() { echo "phase_bootstrap" >> "${phase_log}"; }
phase_install_and_customize() { echo "phase_install_and_customize" >> "${phase_log}"; }
phase_trim() { echo "phase_trim" >> "${phase_log}"; }
phase_pack_runtime() { echo "phase_pack_runtime" >> "${phase_log}"; }
phase_build_iso() { echo "phase_build_iso" >> "${phase_log}"; }
phase_publish_update() { echo "phase_publish_update" >> "${phase_log}"; }

main

assert_equals "$(cat <<'EOF'
phase_prepare
phase_bootstrap
phase_install_and_customize
phase_trim
phase_pack_runtime
phase_build_iso
EOF
)" "$(cat "${phase_log}")" "main phase order"

build_runtime() { echo "build_runtime" >> "${target_log}"; }
main() { echo "main" >> "${target_log}"; }
phase_generate_grub_preview() { echo "phase_generate_grub_preview" >> "${target_log}"; }
phase_publish_update() { echo "phase_publish_update" >> "${target_log}"; }
print_usage() { echo "print_usage" >> "${target_log}"; }

run_build_target runtime
run_build_target publish-update
run_build_target grub-preview
run_build_target help
run_build_target full

assert_equals "$(cat <<'EOF'
build_runtime
build_runtime
phase_publish_update
phase_generate_grub_preview
print_usage
main
EOF
)" "$(cat "${target_log}")" "run_build_target dispatch"

. "${PROJECT_DIR}/scripts/build.sh"

UPDATES_DIR="${tmp_dir}/updates"
RUNTIME_DIR="${tmp_dir}/runtime"
mkdir -p "${RUNTIME_DIR}/${CONTEST_DIR}"
printf 'kernel' > "${RUNTIME_DIR}/${CONTEST_DIR}/vmlinuz"
printf 'initrd' > "${RUNTIME_DIR}/${CONTEST_DIR}/initrd.img"
printf 'sqfs' > "${RUNTIME_DIR}/${CONTEST_DIR}/${ROOT_SQUASH_NAME}"
printf 'grub-entry' > "${RUNTIME_DIR}/${CONTEST_DIR}/grub-entry.cfg"
RUNTIME_VERSION="20260421010101"

phase_publish_update

assert_file "${UPDATES_DIR}/manifest.json"
assert_file "${UPDATES_DIR}/artifacts/${RUNTIME_VERSION}/vmlinuz"
assert_file "${UPDATES_DIR}/artifacts/${RUNTIME_VERSION}/initrd.img"
assert_file "${UPDATES_DIR}/artifacts/${RUNTIME_VERSION}/${ROOT_SQUASH_NAME}"
assert_file "${UPDATES_DIR}/artifacts/${RUNTIME_VERSION}/grub-entry.cfg"

echo "PASS: build.sh preserves helper staging and phase orchestration order."
