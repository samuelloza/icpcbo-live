#!/usr/bin/env bash
# Verifica que el hook de setup.d bloquea el modulo bluetooth por defecto.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${PROJECT_DIR}/scripts/setup.d/common/31-bluetooth-lockdown.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
has()  { grep -Eq -- "$2" "$1" || fail "$1 debe contener /$2/"; }

[ -f "${HOOK}" ] || fail "falta ${HOOK}"
bash -n "${HOOK}" || fail "syntax error en ${HOOK}"
has "${HOOK}" 'install bluetooth /bin/true'
has "${HOOK}" '/etc/modprobe.d/contest-bluetooth.conf'

echo "PASS: bluetooth lockdown"
