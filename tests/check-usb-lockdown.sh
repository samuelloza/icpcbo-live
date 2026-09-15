#!/usr/bin/env bash
# Verifica el bloqueo de almacenamiento externo (USB) y su cableado en el build.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${PROJECT_DIR}/overlay/usr/local/sbin/contest-usb-storage.sh"
HOOK="${PROJECT_DIR}/scripts/setup.d/common/26-usb-lockdown.sh"
UNIT="${PROJECT_DIR}/overlay/etc/systemd/system/contest-usb-policy.service"
RELOAD_TIMER="${PROJECT_DIR}/overlay/etc/systemd/system/contest-usb-reload.timer"
RELOAD_UNIT="${PROJECT_DIR}/overlay/etc/systemd/system/contest-usb-reload.service"

fail() { echo "FAIL: $*" >&2; exit 1; }
has()  { grep -Eq -- "$2" "$1" || fail "$1 debe contener /$2/"; }

bash -n "${SCRIPT}" || fail "syntax error en ${SCRIPT}"
bash -n "${HOOK}"   || fail "syntax error en ${HOOK}"

has "${SCRIPT}" 'install usb_storage /bin/true'
has "${SCRIPT}" 'install uas /bin/true'
has "${UNIT}"   'ExecStart=/usr/local/sbin/contest-usb-storage.sh apply'
has "${HOOK}"   'systemctl enable contest-usb-policy.service'
has "${HOOK}"   'systemctl enable contest-usb-reload.timer'
has "${RELOAD_UNIT}" 'ExecStart=/usr/local/sbin/contest-usb-storage.sh reload'
has "${RELOAD_TIMER}" 'OnUnitActiveSec=30s'
has "${PROJECT_DIR}/config/iso.conf" '^USB_STORAGE_DEFAULT='
has "${PROJECT_DIR}/scripts/build.sh" 'USB_STORAGE_DEFAULT='

tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
bin="${tmp}/bin"; mkdir -p "${bin}"
for c in modprobe udevadm; do printf '#!/bin/sh\nexit 0\n' > "${bin}/${c}"; chmod +x "${bin}/${c}"; done

dropin="${tmp}/contest-usb-storage.conf"
policy="${tmp}/usb-policy.env"
run() { PATH="${bin}:${PATH}" CONTEST_USB_DROPIN="${dropin}" CONTEST_USB_POLICY="${policy}" \
        bash "${SCRIPT}" "$1"; }

run block
[ -f "${dropin}" ] || fail "block no escribio el drop-in"
grep -q 'install usb_storage /bin/true' "${dropin}" || fail "drop-in sin la linea de bloqueo"
grep -qx 'USB_STORAGE=blocked' "${policy}" || fail "policy no quedo en blocked"
[ "$(run status)" = blocked ] || fail "status deberia ser blocked"

run unblock
[ -e "${dropin}" ] && fail "unblock no elimino el drop-in"
grep -qx 'USB_STORAGE=allowed' "${policy}" || fail "policy no quedo en allowed"

printf 'USB_STORAGE=blocked\n' > "${policy}"
run apply
[ -f "${dropin}" ] || fail "apply con policy=blocked debe recrear el drop-in"

run reload
[ -f "${dropin}" ] || fail "reload no debe borrar el drop-in estando bloqueado"

run unblock
run reload
[ ! -e "${dropin}" ] || fail "reload no debe recrear el drop-in estando desbloqueado"

echo "PASS: usb lockdown"
