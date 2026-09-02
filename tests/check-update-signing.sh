#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="${PROJECT_DIR}/scripts/build.sh"
UPDATE_SCRIPT="${PROJECT_DIR}/overlay/usr/lib/contest/update.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_file() {
    [[ -f "$1" ]] || fail "missing file: $1"
}

assert_not_file() {
    [[ ! -e "$1" ]] || fail "unexpected file: $1"
}

assert_contains() {
    grep -Fq "$2" "$1" || fail "$1 does not contain: $2"
}

tmp_dir="$(mktemp -d)"
repo_test_key="$(mktemp "${PROJECT_DIR}/tests/.update-signing-test.XXXXXX")"
trap 'rm -rf "${tmp_dir}"; rm -f "${repo_test_key}"' EXIT

current_private="${tmp_dir}/current-private.pem"
current_public="${tmp_dir}/current-public.pem"
next_private="${tmp_dir}/next-private.pem"
next_public="${tmp_dir}/next-public.pem"
unknown_private="${tmp_dir}/unknown-private.pem"

make_keypair() {
    local private_key="$1"
    local public_key="$2"

    openssl genpkey -algorithm Ed25519 -out "${private_key}" >/dev/null 2>&1
    chmod 0600 "${private_key}"
    openssl pkey -in "${private_key}" -pubout -out "${public_key}" >/dev/null 2>&1
}

make_keypair "${current_private}" "${current_public}"
make_keypair "${next_private}" "${next_public}"
make_keypair "${unknown_private}" "${tmp_dir}/unknown-public.pem"

test_publish_update() {
    local private_key="${tmp_dir}/offline-signing.pem"
    local signature_bin="${tmp_dir}/published-signature.bin"

    cp "${current_private}" "${private_key}"
    chmod 0600 "${private_key}"

    # shellcheck source=../scripts/build.sh
    . "${BUILD_SCRIPT}"
    UPDATES_DIR="${tmp_dir}/published"
    RUNTIME_DIR="${tmp_dir}/runtime"
    RUNTIME_VERSION="2"
    UPDATE_SIGNING_PRIVATE_KEY_FILE="${private_key}"
    UPDATE_NEXT_SIGNING_PUBLIC_KEY_FILE="${next_public}"
    mkdir -p "${RUNTIME_DIR}/${CONTEST_DIR}"
    printf 'kernel' > "${RUNTIME_DIR}/${CONTEST_DIR}/vmlinuz"
    printf 'initrd' > "${RUNTIME_DIR}/${CONTEST_DIR}/initrd.img"
    printf 'squashfs' > "${RUNTIME_DIR}/${CONTEST_DIR}/${ROOT_SQUASH_NAME}"
    printf 'grub-entry' > "${RUNTIME_DIR}/${CONTEST_DIR}/grub-entry.cfg"

    phase_publish_update

    assert_file "${UPDATES_DIR}/manifest.json"
    assert_file "${UPDATES_DIR}/manifest.json.sig"
    [[ "$(wc -l < "${UPDATES_DIR}/manifest.json.sig")" -eq 1 ]] || \
        fail "published signature is not one line"
    [[ "$(tail -c 1 "${UPDATES_DIR}/manifest.json" | od -An -t x1 | tr -d ' ')" = "0a" ]] || \
        fail "canonical manifest lacks final LF"

    python3 - "${UPDATES_DIR}/manifest.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
raw = path.read_bytes()
data = json.loads(raw.decode("utf-8"))
canonical = json.dumps(
    data, ensure_ascii=False, separators=(",", ":"), sort_keys=True
).encode("utf-8") + b"\n"
if raw != canonical:
    raise SystemExit("manifest is not canonical JSON")
PY

    openssl base64 -d -A -in "${UPDATES_DIR}/manifest.json.sig" -out "${signature_bin}"
    openssl pkeyutl -verify -pubin -rawin \
        -inkey "${current_public}" \
        -in "${UPDATES_DIR}/manifest.json" -sigfile "${signature_bin}" >/dev/null
    find "${UPDATES_DIR}" -type f -name '*private*' -o -name '*.pem' | grep -q . && \
        fail "private key material leaked into update output"

    chmod 0644 "${private_key}"
    if (phase_publish_update) >"${tmp_dir}/bad-mode.log" 2>&1; then
        fail "publish-update accepted a private key without mode 0600"
    fi
    chmod 0600 "${private_key}"

    cp "${current_private}" "${repo_test_key}"
    chmod 0600 "${repo_test_key}"
    UPDATE_SIGNING_PRIVATE_KEY_FILE="${repo_test_key}"
    if (phase_publish_update) >"${tmp_dir}/repo-key.log" 2>&1; then
        fail "publish-update accepted a private key inside the repository"
    fi
}

write_manifest() {
    local root="$1"
    local version="$2"
    local next_key="${3:-}"
    local bad_next_hash="${4:-0}"

    python3 - "${root}" "${version}" "${next_key}" "${bad_next_hash}" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
version = sys.argv[2]
next_key_path = sys.argv[3]
bad_next_hash = sys.argv[4] == "1"
artifacts = root / "artifacts"
data = {"artifacts": {}, "version": version}
for name, filename in (
    ("vmlinuz", "vmlinuz"),
    ("initrd_img", "initrd.img"),
    ("filesystem_squashfs", "filesystem.squashfs"),
    ("grub_entry_cfg", "grub-entry.cfg"),
):
    payload = artifacts / filename
    data["artifacts"][name] = {
        "sha256": hashlib.sha256(payload.read_bytes()).hexdigest(),
        "url": payload.as_uri(),
    }
if next_key_path:
    key_bytes = pathlib.Path(next_key_path).read_bytes()
    data["next_signing_key"] = key_bytes.decode("utf-8")
    data["next_signing_key_sha256"] = (
        "0" * 64 if bad_next_hash else hashlib.sha256(key_bytes).hexdigest()
    )
(root / "manifest.json").write_bytes(
    json.dumps(data, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode()
    + b"\n"
)
PY
}

sign_manifest() {
    local root="$1"
    local private_key="$2"

    openssl pkeyutl -sign -rawin -inkey "${private_key}" \
        -in "${root}/manifest.json" -out "${root}/manifest.sig.bin"
    openssl base64 -A -in "${root}/manifest.sig.bin" > "${root}/manifest.json.sig"
    printf '\n' >> "${root}/manifest.json.sig"
}

prepare_client_case() {
    local root="$1"
    local version="$2"
    local next_key="${3:-}"
    local bad_next_hash="${4:-0}"
    local contest_dir="/icpc_bo"
    local target_root="${root}/target"

    mkdir -p "${root}/media${contest_dir}" "${target_root}${contest_dir}/current" \
        "${target_root}${contest_dir}/state" "${root}/artifacts" "${root}/bin"
    printf 'contest_dir=%s\n' "${contest_dir}" > "${root}/cmdline"
    printf 'tmpfs %s tmpfs rw 0 0\n' "${root}/media" > "${root}/mounts"
    cat > "${root}/media${contest_dir}/.contest-installed" <<EOF
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
    printf 'kernel-%s' "${version}" > "${root}/artifacts/vmlinuz"
    printf 'initrd-%s' "${version}" > "${root}/artifacts/initrd.img"
    printf 'squashfs-%s' "${version}" > "${root}/artifacts/filesystem.squashfs"
    printf 'grub-%s' "${version}" > "${root}/artifacts/grub-entry.cfg"
    write_manifest "${root}" "${version}" "${next_key}" "${bad_next_hash}"

    cat > "${root}/update.env" <<EOF
UPDATE_MANIFEST_URL=file://${root}/manifest.json
UPDATE_CHECK_ON_BOOT=true
UPDATE_SIGNATURE_PUBKEY=${current_public}
RUNTIME_VERSION=1
EOF
    cat > "${root}/bin/mount" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
src="${@: -2:1}"
dst="${@: -1}"
rm -rf "${dst}"
ln -s "${src}" "${dst}"
EOF
    cat > "${root}/bin/umount" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
rm -rf "${@: -1}"
EOF
    cat > "${root}/bin/mountpoint" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" = "-q" ]] && shift
[[ -L "${1:-}" || -d "${1:-}" ]]
EOF
    chmod +x "${root}/bin/"*
}

run_client() {
    local root="$1"

    PATH="${root}/bin:${PATH}" \
    CONTEST_UPDATE_ENV="${root}/update.env" \
    CONTEST_UPDATE_LOG="${root}/update.log" \
    CONTEST_UPDATE_MOUNT_TMP="${root}/mounted" \
    CONTEST_UPDATE_SKIP_ROOT_CHECK=1 \
    PROC_MOUNTS_FILE="${root}/mounts" \
    CMDLINE_FILE="${root}/cmdline" \
    CONTEST_MEDIA_ROOT_OVERRIDE="${root}/media" \
    bash "${UPDATE_SCRIPT}"
}

assert_rejected_without_parsing() {
    local root="$1"
    local label="$2"

    if run_client "${root}" >"${root}/stdout" 2>&1; then
        fail "${label} was accepted"
    fi
    assert_contains "${root}/update.log" "Manifest signature verification failed"
    grep -Fq "Downloading" "${root}/update.log" && \
        fail "${label} reached artifact URL processing"
    assert_contains "${root}/target/icpc_bo/current/vmlinuz" "old-kernel"
}

test_client_signatures_and_rotation() {
    local root

    root="${tmp_dir}/valid"
    prepare_client_case "${root}" 2
    sign_manifest "${root}" "${current_private}"
    run_client "${root}"
    assert_contains "${root}/target/icpc_bo/current/vmlinuz" "kernel-2"

    root="${tmp_dir}/tampered"
    prepare_client_case "${root}" 2
    sign_manifest "${root}" "${current_private}"
    python3 - "${root}/manifest.json" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_bytes(p.read_bytes().replace(b'"version":"2"', b'"version":"9"'))
PY
    assert_rejected_without_parsing "${root}" "altered manifest byte"

    root="${tmp_dir}/wrong-signature"
    prepare_client_case "${root}" 2
    sign_manifest "${root}" "${next_private}"
    assert_rejected_without_parsing "${root}" "different signature"

    root="${tmp_dir}/unknown-key"
    prepare_client_case "${root}" 2
    sign_manifest "${root}" "${unknown_private}"
    assert_rejected_without_parsing "${root}" "unknown signing key"

    root="${tmp_dir}/rotation-valid"
    prepare_client_case "${root}" 2 "${next_public}"
    sign_manifest "${root}" "${current_private}"
    run_client "${root}"
    assert_file "${root}/target/icpc_bo/state/update-signing-pending.pub"
    cmp -s "${next_public}" \
        "${root}/target/icpc_bo/state/update-signing-pending.pub" || \
        fail "valid rotation did not install the expected pending key"

    printf 'kernel-3' > "${root}/artifacts/vmlinuz"
    printf 'initrd-3' > "${root}/artifacts/initrd.img"
    printf 'squashfs-3' > "${root}/artifacts/filesystem.squashfs"
    printf 'grub-3' > "${root}/artifacts/grub-entry.cfg"
    write_manifest "${root}" 3
    sign_manifest "${root}" "${current_private}"
    if run_client "${root}" >"${root}/old-key-stdout" 2>&1; then
        fail "current key bypassed an installed pending rotation"
    fi
    assert_contains "${root}/update.log" "Pending signing key is required for the next update version"
    assert_contains "${root}/target/icpc_bo/current/vmlinuz" "kernel-2"

    sign_manifest "${root}" "${next_private}"
    run_client "${root}"
    assert_file "${root}/target/icpc_bo/state/update-signing-current.pub"
    assert_not_file "${root}/target/icpc_bo/state/update-signing-pending.pub"
    cmp -s "${next_public}" \
        "${root}/target/icpc_bo/state/update-signing-current.pub" || \
        fail "pending key was not promoted after verifying the next version"

    root="${tmp_dir}/rotation-invalid"
    prepare_client_case "${root}" 2 "${next_public}" 1
    sign_manifest "${root}" "${current_private}"
    if run_client "${root}" >"${root}/stdout" 2>&1; then
        fail "rotation with an invalid key hash was accepted"
    fi
    assert_contains "${root}/update.log" "next_signing_key_sha256 mismatch"
    assert_not_file "${root}/target/icpc_bo/state/update-signing-pending.pub"
    assert_contains "${root}/target/icpc_bo/current/vmlinuz" "old-kernel"
}

test_signature_rejects_tamper() {
    local root="${tmp_dir}/signature-tamper"
    local signature_bin="${tmp_dir}/signature-tamper.bin"

    prepare_client_case "${root}" 2
    sign_manifest "${root}" "${current_private}"
    openssl base64 -d -A -in "${root}/manifest.json.sig" -out "${signature_bin}"
    openssl pkeyutl -verify -pubin -rawin         -inkey "${current_public}"         -in "${root}/manifest.json" -sigfile "${signature_bin}" >/dev/null
    python3 - "${root}/manifest.json" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_bytes(p.read_bytes().replace(b'"version":"2"', b'"version":"9"'))
PY
    if openssl pkeyutl -verify -pubin -rawin         -inkey "${current_public}"         -in "${root}/manifest.json" -sigfile "${signature_bin}" >/dev/null 2>&1; then
        fail "altered manifest unexpectedly verifies"
    fi
}

test_signature_rejects_tamper
test_publish_update
test_client_signatures_and_rotation

echo "PASS: update publication and client enforce the Ed25519 trust chain."
