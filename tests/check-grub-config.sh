#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "${PROJECT_DIR}/config/iso.conf"
# shellcheck source=/dev/null
source "${PROJECT_DIR}/scripts/build/grub.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_contains() {
    grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

GRUB_ADMIN_PASSWORD_HASH="grub.pbkdf2.sha512.10000.ABCD0123.DEADBEEF"
runtime_grub="${tmp_dir}/grub-entry.cfg"
iso_grub="${tmp_dir}/grub.cfg"

write_runtime_grub_entry "${runtime_grub}"
write_iso_grub_cfg "${iso_grub}"

for config in "${runtime_grub}" "${iso_grub}"; do
    assert_contains "${config}" 'set superusers="contestadmin"'
    assert_contains "${config}" \
        "password_pbkdf2 contestadmin ${GRUB_ADMIN_PASSWORD_HASH}"
    assert_contains "${config}" "linux /${CONTEST_DIR}/vmlinuz"
    assert_contains "${config}" "initrd /${CONTEST_DIR}/initrd.img"
done

assert_contains "${runtime_grub}" \
    "menuentry \"${ISO_NAME} (folder mode)\" --unrestricted {"
assert_contains "${iso_grub}" \
    'menuentry "Iniciar ICPC BO (persistencia del home)" --unrestricted {'
assert_contains "${iso_grub}" 'contest.reset_home=1'
assert_contains "${iso_grub}" 'contest.clean_install=1'
if grep -Eq '\|\||&&' "${iso_grub}"; then
    fail "GRUB config no debe contener operadores de shell inválidos"
fi
assert_contains "${iso_grub}" 'search --no-floppy --quiet --set=hdd_root'

# El despliegue LAN es responsabilidad exclusiva de mini-deploy.
if grep -Fq 'Despliegue masivo por red (LAN / torrent)' "${iso_grub}" || \
   grep -Fq 'contest.install_mode=deploy' "${iso_grub}"; then
    fail "main GRUB must not expose the mini-deploy LAN flow"
fi

# GRUB y el kernel usan sólo la consola gráfica.
assert_contains "${iso_grub}" 'terminal_output gfxterm'
if grep -q 'ttyS0' "${iso_grub}" || grep -q '^serial ' "${iso_grub}"; then
    fail "GRUB no debe configurar consola serial"
fi

if grep -E 'menuentry "(Limpiar home|Borrar archivos de instalacion)" --unrestricted' \
    "${iso_grub}" >/dev/null; then
    fail "destructive menu entries must require the GRUB administrator"
fi

GRUB_ADMIN_PASSWORD_HASH=""
if write_iso_grub_cfg "${tmp_dir}/unprotected.cfg" >/dev/null 2>&1; then
    fail "GRUB generation must fail closed without a PBKDF2 hash"
fi
[[ ! -e "${tmp_dir}/unprotected.cfg" ]] || \
    fail "failed GRUB generation left an unprotected config"

echo "PASS: GRUB generates authenticated administrative entries and unrestricted normal boots."
