#!/usr/bin/env bash

set -euo pipefail

. "${CONTEST_COMMON_SH:-/usr/lib/contest/common.sh}"

LOG="${CONTEST_UPDATE_LOG:-/var/log/contest-update.log}"
MOUNT_TMP="${CONTEST_UPDATE_MOUNT_TMP:-/mnt/contest-update-target}"
UPDATE_ENV="${CONTEST_UPDATE_ENV:-/etc/contestiso/update.env}"
PROC_MOUNTS_FILE="${PROC_MOUNTS_FILE:-/proc/mounts}"
CONTEST_MEDIA_ROOT="${CONTEST_MEDIA_ROOT:-/run/contest-media}"

log() {
    local ts
    ts=$(date -u +%H:%M:%S)
    echo "[${ts}] $*" | tee -a "${LOG}"
}

trap 'mountpoint -q "${MOUNT_TMP}" 2>/dev/null && umount "${MOUNT_TMP}" || true' EXIT

mkdir -p "$(dirname "${LOG}")"

if [ "${CONTEST_UPDATE_SKIP_ROOT_CHECK:-0}" != "1" ] && [ "$(id -u)" -ne 0 ]; then
    log "FATAL: Must run as root"
    exit 1
fi

if [ ! -r "${UPDATE_ENV}" ]; then
    log "No update config found. Skipping."
    exit 0
fi

. "${UPDATE_ENV}"

if [ "${UPDATE_CHECK_ON_BOOT:-true}" != "true" ]; then
    log "Automatic updates disabled. Skipping."
    exit 0
fi

if [ -z "${UPDATE_MANIFEST_URL:-}" ]; then
    log "UPDATE_MANIFEST_URL is empty. Skipping."
    exit 0
fi

BOOT_FSTYPE="$(awk '$2=="'"${CONTEST_MEDIA_ROOT}"'" {print $3; exit}' "${PROC_MOUNTS_FILE}")"
if [ "${BOOT_FSTYPE:-}" = "iso9660" ]; then
    log "Running from ISO base. Skipping runtime auto-update."
    exit 0
fi

CONTEST_DIR="$(cmdline_param contest_dir)"
CONTEST_DIR="$(normalize_contest_dir "${CONTEST_DIR:-/contest}")"

if [ -f "${CONTEST_MEDIA_ROOT}${CONTEST_DIR}/.contest-installed" ]; then
    read_install_marker "${CONTEST_MEDIA_ROOT}${CONTEST_DIR}/.contest-installed"
elif [ -f "${CONTEST_MEDIA_ROOT}${CONTEST_DIR}/.contest-full-installed" ]; then
    log "Full install detected. Progressive runtime updates are not enabled for this mode yet. Skipping."
    exit 0
else
    log "No portable install marker found. Skipping."
    exit 0
fi

if [ -z "${MARKER_TARGET_DEV:-}" ] || [ -z "${MARKER_TARGET_FSTYPE:-}" ]; then
    log "FATAL: Install marker is incomplete"
    exit 1
fi

mkdir -p "${MOUNT_TMP}"
mount -t "${MARKER_TARGET_FSTYPE}" -o "$(mount_opts_for_fstype "${MARKER_TARGET_FSTYPE}" rw)" "${MARKER_TARGET_DEV}" "${MOUNT_TMP}" || {
    log "FATAL: Cannot mount ${MARKER_TARGET_DEV} read-write"
    exit 1
}

contest_root="${MOUNT_TMP}${CONTEST_DIR}"
if [ ! -d "${contest_root}" ]; then
    log "FATAL: Contest root missing on target: ${contest_root}"
    exit 1
fi

local_version="$(read_runtime_version "${contest_root}" 2>/dev/null || printf '%s' "${RUNTIME_VERSION:-dev}")"
manifest_tmp="$(mktemp)"

curl --fail --silent --show-error --location "${UPDATE_MANIFEST_URL}" -o "${manifest_tmp}" || {
    log "FATAL: Cannot download manifest: ${UPDATE_MANIFEST_URL}"
    exit 1
}

manifest_info="$(python3 - "${manifest_tmp}" "${UPDATE_MANIFEST_URL}" <<'PY'
import json, sys
from urllib.parse import urljoin

manifest_path, base_url = sys.argv[1:3]
with open(manifest_path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)

print(f"VERSION\t{data.get('version', '')}")
for name, meta in data.get('artifacts', {}).items():
    print(f"ARTIFACT\t{name}\t{urljoin(base_url, meta.get('url', ''))}\t{meta.get('sha256', '')}")
PY
)"

remote_version="$(printf '%s\n' "${manifest_info}" | awk -F '\t' '$1=="VERSION" {print $2; exit}')"
if [ -z "${remote_version}" ]; then
    log "FATAL: Manifest does not define version"
    exit 1
fi

if [ "${remote_version}" = "${local_version}" ]; then
    log "Already at version ${local_version}. No update needed."
    exit 0
fi

artifact_lines="$(printf '%s\n' "${manifest_info}" | awk -F '\t' '$1=="ARTIFACT" {print}')"
if [ -z "${artifact_lines}" ]; then
    log "FATAL: Manifest does not define any artifacts"
    exit 1
fi

staging_root="$(contest_staging_dir "${contest_root}")/${remote_version}"
current_dir="$(contest_current_dir "${contest_root}")"
previous_dir="$(contest_previous_dir "${contest_root}")"
state_dir="$(contest_state_dir "${contest_root}")"
mkdir -p "${staging_root}" "${state_dir}"

while IFS=$'\t' read -r _kind name url sha; do
    case "${name}" in
        vmlinuz) out_name="vmlinuz" ;;
        initrd_img) out_name="initrd.img" ;;
        filesystem_squashfs) out_name="filesystem.squashfs" ;;
        grub_entry_cfg) out_name="grub-entry.cfg" ;;
        *) continue ;;
    esac

    if [ -z "${url}" ] || [ -z "${sha}" ]; then
        log "FATAL: Manifest artifact ${name} is incomplete"
        exit 1
    fi

    dest="${staging_root}/${out_name}"
    log "Downloading ${name}..."
    curl --fail --silent --show-error --location "${url}" -o "${dest}" || {
        log "FATAL: Cannot download artifact ${name}"
        exit 1
    }

    if [ "$(sha256sum "${dest}" | awk '{print $1}')" != "${sha}" ]; then
        log "FATAL: SHA256 mismatch for ${name}"
        exit 1
    fi
done <<< "${artifact_lines}"

for required in vmlinuz initrd.img filesystem.squashfs; do
    if [ ! -f "${staging_root}/${required}" ]; then
        log "FATAL: Missing staged ${required}"
        exit 1
    fi
done

printf '%s\n' "${remote_version}" > "${staging_root}/VERSION"

[ -d "${previous_dir}" ] && rm -rf "${previous_dir}"
[ -d "${current_dir}" ] && mv "${current_dir}" "${previous_dir}"
mv "${staging_root}" "${current_dir}"

write_runtime_version "${contest_root}" "${remote_version}"
link_runtime_files "${contest_root}"
cp "${manifest_tmp}" "${contest_root}/manifest.json"

cat > "${state_dir}/last-update.json" <<EOF
{"version":"${remote_version}","previous_version":"${local_version}","status":"applied","reboot_required":true}
EOF

log "Update applied: ${local_version} -> ${remote_version}. Reboot recommended."
