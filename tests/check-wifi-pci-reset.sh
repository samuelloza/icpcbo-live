#!/usr/bin/env bash
# Verifica el reset de controladores wifi PCI y su cableado en el build.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${PROJECT_DIR}/overlay/usr/local/sbin/contest-wifi-pci-reset.sh"
HOOK="${PROJECT_DIR}/scripts/setup.d/common/33-wifi-pci-reset.sh"
UNIT="${PROJECT_DIR}/overlay/etc/systemd/system/contest-wifi-pci-reset.service"

fail() { echo "FAIL: $*" >&2; exit 1; }
has()  { grep -Eq -- "$2" "$1" || fail "$1 debe contener /$2/"; }

bash -n "${SCRIPT}" || fail "syntax error en ${SCRIPT}"
bash -n "${HOOK}"   || fail "syntax error en ${HOOK}"

has "${UNIT}" 'ExecStart=/usr/local/sbin/contest-wifi-pci-reset.sh'
has "${UNIT}" 'Before=network-pre.target NetworkManager.service'
has "${HOOK}" 'systemctl enable contest-wifi-pci-reset.service'

# Simula un sysfs con un controlador de red PCI (clase 0280xx) con driver.
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
sys="${tmp}/sys/bus/pci"
dev="${sys}/devices/0000:03:00.0"
drv="${sys}/drivers/iwlwifi"

mkdir -p "${dev}" "${drv}"
echo "0x028000" > "${dev}/class"
echo -n > "${dev}/reset"
echo -n > "${drv}/unbind"
echo -n > "${drv}/bind"
echo -n > "${sys}/drivers_probe"
ln -s ../../drivers/iwlwifi "${dev}/driver"

CONTEST_PCI_SYSFS="${sys}" bash "${SCRIPT}" >/dev/null

[ "$(cat "${drv}/unbind")" = "0000:03:00.0" ] || fail "no hizo unbind del BDF"
[ "$(cat "${dev}/reset")" = "1" ] || fail "no escribio 1 en reset"
[ "$(cat "${drv}/bind")" = "0000:03:00.0" ] || fail "no hizo rebind por el driver original"
[ ! -s "${sys}/drivers_probe" ] || fail "no deberia usar drivers_probe si el bind directo funciona"

echo "PASS: wifi pci reset"
