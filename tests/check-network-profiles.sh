#!/usr/bin/env bash
# Los perfiles de NetworkManager que el operador configura en el mini (WiFi, IP
# fija) se copian a <CONTEST_DIR>/network y el initramfs los repone en cada
# arranque. Si un lado renombra el directorio, el equipo por WiFi pierde la red
# tras el kexec sin que nada falle ruidosamente: este test ata los dos lados.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INITRAMFS_LOCAL="${PROJECT_DIR}/overlay/etc/initramfs-tools/scripts/local"
MINI_FETCH="${PROJECT_DIR}/mini-deploy/overlay/usr/lib/mini-deploy/lan-fetch.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

grep -q '/run/contest-media${CONTEST_DIR}/network' "${INITRAMFS_LOCAL}" \
    || fail "el initramfs ya no lee <CONTEST_DIR>/network del medio"
grep -q 'etc/NetworkManager/system-connections' "${INITRAMFS_LOCAL}" \
    || fail "el initramfs ya no repone los perfiles en system-connections"

if [[ -f "${MINI_FETCH}" ]]; then
    grep -q '"${runtime}/network"' "${MINI_FETCH}" \
        || fail "el mini ya no escribe los perfiles en <runtime>/network"
fi

echo "PASS: los perfiles de red del mini se reponen en el runtime en cada arranque."
