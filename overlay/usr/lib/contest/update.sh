#!/usr/bin/env bash

set -euo pipefail

if [ -r /usr/lib/contest/lib/base.sh ]; then
    . /usr/lib/contest/lib/base.sh
    . /usr/lib/contest/lib/fs.sh
    . /usr/lib/contest/lib/runtime-layout.sh
else
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    . "${lib_dir}/lib/base.sh"
    . "${lib_dir}/lib/fs.sh"
    . "${lib_dir}/lib/runtime-layout.sh"
fi

LOG="/var/log/contest-update.log"
MOUNT_TMP="/mnt/contest-update-target"
UPDATE_ENV="/etc/contestiso/update.env"
PROC_MOUNTS_FILE="/proc/mounts"
CONTEST_MEDIA_ROOT="/run/contest-media"

if [ -n "${CONTEST_UPDATE_LOG:-}" ]; then
    LOG="${CONTEST_UPDATE_LOG}"
fi
if [ -n "${CONTEST_UPDATE_MOUNT_TMP:-}" ]; then
    MOUNT_TMP="${CONTEST_UPDATE_MOUNT_TMP}"
fi
if [ -n "${CONTEST_UPDATE_ENV:-}" ]; then
    UPDATE_ENV="${CONTEST_UPDATE_ENV}"
fi
if [ -n "${PROC_MOUNTS_FILE_OVERRIDE:-}" ]; then
    PROC_MOUNTS_FILE="${PROC_MOUNTS_FILE_OVERRIDE}"
fi
if [ -n "${CONTEST_MEDIA_ROOT_OVERRIDE:-}" ]; then
    CONTEST_MEDIA_ROOT="${CONTEST_MEDIA_ROOT_OVERRIDE}"
fi

log() {
    local ts
    ts=$(date -u +%H:%M:%S)
    echo "[${ts}] $*" | tee -a "${LOG}"
}

die() {
    log "FATAL: $*"
    exit 1
}

download_file() {
    local url="$1"
    local dest="$2"

    curl --fail --silent --show-error --location "${url}" -o "${dest}"
}

install_public_key() {
    local source="$1"
    local destination="$2"

    if [ "${CONTEST_UPDATE_SKIP_ROOT_CHECK:-0}" = "1" ]; then
        install -m 0644 "${source}" "${destination}"
    else
        install -o root -g root -m 0644 "${source}" "${destination}"
    fi
}

mount_target_rw() {
    local mount_opts

    mount_opts="$(mount_opts_for_fstype "${MARKER_TARGET_FSTYPE}" rw)"
    mkdir -p "${MOUNT_TMP}"
    mount -t "${MARKER_TARGET_FSTYPE}" -o "${mount_opts}" "${MARKER_TARGET_DEV}" "${MOUNT_TMP}"
}

trap 'mountpoint -q "${MOUNT_TMP}" 2>/dev/null && umount "${MOUNT_TMP}" || true' EXIT

mkdir -p "$(dirname "${LOG}")"

if [ "${CONTEST_UPDATE_SKIP_ROOT_CHECK:-0}" != "1" ] && [ "$(id -u)" -ne 0 ]; then
    die "Must run as root"
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
else
    log "No portable install marker found. Skipping."
    exit 0
fi

if [ -z "${MARKER_TARGET_DEV:-}" ] || [ -z "${MARKER_TARGET_FSTYPE:-}" ]; then
    die "Install marker is incomplete"
fi

mount_target_rw || die "Cannot mount ${MARKER_TARGET_DEV} read-write"

contest_root="${MOUNT_TMP}${CONTEST_DIR}"
if [ ! -d "${contest_root}" ]; then
    die "Contest root missing on target: ${contest_root}"
fi

local_version="$(read_runtime_version "${contest_root}" 2>/dev/null || printf '%s' "${RUNTIME_VERSION:-dev}")"
manifest_tmp="$(mktemp)"
signature_tmp="$(mktemp)"
signature_bin_tmp="$(mktemp)"
next_key_tmp="$(mktemp)"
trap 'rm -f "${manifest_tmp:-}" "${signature_tmp:-}" "${signature_bin_tmp:-}" "${next_key_tmp:-}"; mountpoint -q "${MOUNT_TMP}" 2>/dev/null && umount "${MOUNT_TMP}" || true' EXIT

state_dir="$(contest_state_dir "${contest_root}")"
current_key="${state_dir}/update-signing-current.pub"
pending_key="${state_dir}/update-signing-pending.pub"
provisioned_key="/usr/share/contest/keys/update-signing.pub"
[ -n "${UPDATE_SIGNATURE_PUBKEY:-}" ] && provisioned_key="${UPDATE_SIGNATURE_PUBKEY}"
signature_url="${UPDATE_MANIFEST_SIGNATURE_URL:-${UPDATE_MANIFEST_URL}.sig}"
mkdir -p "${state_dir}"

download_file "${UPDATE_MANIFEST_URL}" "${manifest_tmp}" || die "Cannot download manifest: ${UPDATE_MANIFEST_URL}"
download_file "${signature_url}" "${signature_tmp}" || die "Cannot download manifest signature: ${signature_url}"

if ! grep -Eq '^[A-Za-z0-9+/]+={0,2}$' "${signature_tmp}" || [ "$(wc -l < "${signature_tmp}")" -ne 1 ]; then
    die "Manifest signature must be one base64 line"
fi
openssl base64 -d -A -in "${signature_tmp}" -out "${signature_bin_tmp}" 2>/dev/null || \
    die "Manifest signature is not valid base64"

trusted_key="${current_key}"
[ -r "${trusted_key}" ] || trusted_key="${provisioned_key}"
[ -r "${trusted_key}" ] || die "Update signing public key is unavailable: ${trusted_key}"

verification_key_kind="current"
if [ -r "${pending_key}" ] && openssl pkeyutl -verify -pubin -rawin \
    -inkey "${pending_key}" -in "${manifest_tmp}" -sigfile "${signature_bin_tmp}" >/dev/null 2>&1; then
    verification_key_kind="pending"
elif ! openssl pkeyutl -verify -pubin -rawin \
    -inkey "${trusted_key}" -in "${manifest_tmp}" -sigfile "${signature_bin_tmp}" >/dev/null 2>&1; then
    die "Manifest signature verification failed"
fi

manifest_info="$(python3 - "${manifest_tmp}" "${UPDATE_MANIFEST_URL}" <<'PY'
import base64
import json, sys
from urllib.parse import urljoin

manifest_path, base_url = sys.argv[1:3]
with open(manifest_path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)

print(f"VERSION\t{data.get('version', '')}")
for name, meta in data.get('artifacts', {}).items():
    print(f"ARTIFACT\t{name}\t{urljoin(base_url, meta.get('url', ''))}\t{meta.get('sha256', '')}")

next_key = data.get("next_signing_key")
next_key_sha256 = data.get("next_signing_key_sha256")
if (next_key is None) != (next_key_sha256 is None):
    raise SystemExit("next signing key fields must be provided together")
if next_key is not None:
    encoded = base64.b64encode(next_key.encode("utf-8")).decode("ascii")
    print(f"NEXT_KEY\t{encoded}\t{next_key_sha256}")
PY
)" || die "Manifest JSON is invalid"

remote_version="$(printf '%s\n' "${manifest_info}" | awk -F '\t' '$1=="VERSION" {print $2; exit}')"
if [ -z "${remote_version}" ]; then
    die "Manifest does not define version"
fi

if [ -r "${pending_key}" ] && [ "${verification_key_kind}" != "pending" ] && \
    [ "${remote_version}" != "${local_version}" ]; then
    die "Pending signing key is required for the next update version"
fi

if [ "${remote_version}" = "${local_version}" ]; then
    log "Already at version ${local_version}. No update needed."
    exit 0
fi

artifact_lines="$(printf '%s\n' "${manifest_info}" | awk -F '\t' '$1=="ARTIFACT" {print}')"
if [ -z "${artifact_lines}" ]; then
    die "Manifest does not define any artifacts"
fi

next_key_line="$(printf '%s\n' "${manifest_info}" | awk -F '\t' '$1=="NEXT_KEY" {print; exit}')"
if [ -n "${next_key_line}" ]; then
    IFS=$'\t' read -r _kind next_key_b64 next_key_sha256 <<< "${next_key_line}"
    printf '%s' "${next_key_b64}" | openssl base64 -d -A > "${next_key_tmp}" 2>/dev/null || \
        die "next_signing_key is not valid base64 data"
    [ "$(sha256sum "${next_key_tmp}" | awk '{print $1}')" = "${next_key_sha256}" ] || \
        die "next_signing_key_sha256 mismatch"
    openssl pkey -pubin -in "${next_key_tmp}" -text -noout 2>/dev/null | \
        grep -q '^ED25519 Public-Key:' || \
        die "next_signing_key is not a valid Ed25519 public key"
fi

staging_root="$(contest_staging_dir "${contest_root}")/${remote_version}"
current_dir="$(contest_current_dir "${contest_root}")"
previous_dir="$(contest_previous_dir "${contest_root}")"
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
        die "Manifest artifact ${name} is incomplete"
    fi

    dest="${staging_root}/${out_name}"
    log "Downloading ${name}..."
    download_file "${url}" "${dest}" || die "Cannot download artifact ${name}"

    if [ "$(sha256sum "${dest}" | awk '{print $1}')" != "${sha}" ]; then
        die "SHA256 mismatch for ${name}"
    fi
done <<< "${artifact_lines}"

for required in vmlinuz initrd.img filesystem.squashfs; do
    if [ ! -f "${staging_root}/${required}" ]; then
        die "Missing staged ${required}"
    fi
done

printf '%s\n' "${remote_version}" > "${staging_root}/VERSION"

[ -d "${previous_dir}" ] && rm -rf "${previous_dir}"
[ -d "${current_dir}" ] && mv "${current_dir}" "${previous_dir}"
mv "${staging_root}" "${current_dir}"

write_runtime_version "${contest_root}" "${remote_version}"
link_runtime_files "${contest_root}"
cp "${manifest_tmp}" "${contest_root}/manifest.json"
cp "${signature_tmp}" "${contest_root}/manifest.json.sig"

if [ "${verification_key_kind}" = "pending" ]; then
    install_public_key "${pending_key}" "${current_key}"
    rm -f "${pending_key}"
fi
if [ -n "${next_key_line}" ]; then
    install_public_key "${next_key_tmp}" "${pending_key}"
fi

cat > "${state_dir}/last-update.json" <<EOF
{"version":"${remote_version}","previous_version":"${local_version}","status":"applied","reboot_required":true}
EOF

log "Update applied: ${local_version} -> ${remote_version}. Reboot recommended."
