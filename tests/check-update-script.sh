#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE_SCRIPT="${PROJECT_DIR}/overlay/usr/lib/contest/update.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_file() {
    local path="$1"
    [[ -f "${path}" ]] || fail "missing file: ${path}"
}

assert_contains() {
    local needle="$1"
    local haystack="$2"
    local label="$3"
    case "${haystack}" in
        *"${needle}"*) ;;
        *) fail "${label} does not contain '${needle}'" ;;
    esac
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

contest_dir="/icpc_bo"
media_root="${tmp_dir}/contest-media"
target_root="${tmp_dir}/target-root"
mounted_root="${tmp_dir}/mounted-root"
bin_dir="${tmp_dir}/bin"
update_env="${tmp_dir}/update.env"
proc_mounts="${tmp_dir}/mounts"
cmdline_file="${tmp_dir}/cmdline"
manifest_file="${tmp_dir}/manifest.json"
artifacts_dir="${tmp_dir}/artifacts"

mkdir -p "${media_root}${contest_dir}" "${target_root}${contest_dir}/current" "${target_root}${contest_dir}/state" "${artifacts_dir}" "${bin_dir}"

printf 'contest_dir=%s\n' "${contest_dir}" > "${cmdline_file}"
printf 'tmpfs %s tmpfs rw 0 0\n' "${media_root}" > "${proc_mounts}"

cat > "${media_root}${contest_dir}/.contest-installed" <<EOF
INSTALL_TYPE=portable
TARGET_DEV=${target_root}
TARGET_FSTYPE=ext4
CONTEST_DIR=${contest_dir}
CONTEST_ROOT=filesystem.squashfs
EOF

printf 'old-kernel' > "${target_root}${contest_dir}/current/vmlinuz"
printf 'old-initrd' > "${target_root}${contest_dir}/current/initrd.img"
printf 'old-squashfs' > "${target_root}${contest_dir}/current/filesystem.squashfs"
printf 'old-grub-entry' > "${target_root}${contest_dir}/current/grub-entry.cfg"
printf '1\n' > "${target_root}${contest_dir}/current/VERSION"
printf '1\n' > "${target_root}${contest_dir}/VERSION"
ln -sfn current/vmlinuz "${target_root}${contest_dir}/vmlinuz"
ln -sfn current/initrd.img "${target_root}${contest_dir}/initrd.img"
ln -sfn current/filesystem.squashfs "${target_root}${contest_dir}/filesystem.squashfs"
ln -sfn current/grub-entry.cfg "${target_root}${contest_dir}/grub-entry.cfg"

printf 'new-kernel' > "${artifacts_dir}/vmlinuz"
printf 'new-initrd' > "${artifacts_dir}/initrd.img"
printf 'new-squashfs' > "${artifacts_dir}/filesystem.squashfs"
printf 'new-grub-entry' > "${artifacts_dir}/grub-entry.cfg"

kernel_sha="$(sha256sum "${artifacts_dir}/vmlinuz" | awk '{print $1}')"
initrd_sha="$(sha256sum "${artifacts_dir}/initrd.img" | awk '{print $1}')"
sqfs_sha="$(sha256sum "${artifacts_dir}/filesystem.squashfs" | awk '{print $1}')"
grub_sha="$(sha256sum "${artifacts_dir}/grub-entry.cfg" | awk '{print $1}')"

cat > "${manifest_file}" <<EOF
{
  "version": "2",
  "artifacts": {
    "vmlinuz": {"url": "file://${artifacts_dir}/vmlinuz", "sha256": "${kernel_sha}"},
    "initrd_img": {"url": "file://${artifacts_dir}/initrd.img", "sha256": "${initrd_sha}"},
    "filesystem_squashfs": {"url": "file://${artifacts_dir}/filesystem.squashfs", "sha256": "${sqfs_sha}"},
    "grub_entry_cfg": {"url": "file://${artifacts_dir}/grub-entry.cfg", "sha256": "${grub_sha}"}
  }
}
EOF

cat > "${update_env}" <<EOF
UPDATE_MANIFEST_URL=file://${manifest_file}
UPDATE_CHECK_ON_BOOT=true
RUNTIME_VERSION=1
EOF

cat > "${bin_dir}/mount" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
src="${@: -2:1}"
dst="${@: -1}"
rm -rf "${dst}"
ln -s "${src}" "${dst}"
EOF
cat > "${bin_dir}/umount" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
target="${@: -1}"
rm -rf "${target}"
EOF
cat > "${bin_dir}/mountpoint" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" = "-q" ]] && shift
target="${1:-}"
[[ -L "${target}" || -d "${target}" ]]
EOF
chmod +x "${bin_dir}/mount" "${bin_dir}/umount" "${bin_dir}/mountpoint"

PATH="${bin_dir}:${PATH}" \
CONTEST_UPDATE_ENV="${update_env}" \
CONTEST_UPDATE_LOG="${tmp_dir}/contest-update.log" \
CONTEST_UPDATE_MOUNT_TMP="${mounted_root}" \
CONTEST_UPDATE_SKIP_ROOT_CHECK=1 \
PROC_MOUNTS_FILE="${proc_mounts}" \
CMDLINE_FILE="${cmdline_file}" \
CONTEST_MEDIA_ROOT="${media_root}" \
bash "${UPDATE_SCRIPT}"

assert_file "${target_root}${contest_dir}/current/vmlinuz"
assert_file "${target_root}${contest_dir}/previous/vmlinuz"
assert_contains 'new-kernel' "$(<"${target_root}${contest_dir}/current/vmlinuz")" "current kernel"
assert_contains 'old-kernel' "$(<"${target_root}${contest_dir}/previous/vmlinuz")" "previous kernel"
assert_contains '2' "$(<"${target_root}${contest_dir}/VERSION")" "top-level version"
assert_contains '2' "$(<"${target_root}${contest_dir}/current/VERSION")" "current version"
assert_file "${target_root}${contest_dir}/manifest.json"
assert_file "${target_root}${contest_dir}/state/last-update.json"
assert_contains 'reboot_required' "$(<"${target_root}${contest_dir}/state/last-update.json")" "update state"

echo "PASS: update.sh downloads and activates a new runtime version."
