#!/usr/bin/env bash
# Verifica que el hook de identidad del sistema fija /etc/adjtime segun
# HWCLOCK_LOCAL (RTC en hora local por defecto: PCs de sede ex-Windows).
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${PROJECT_DIR}/scripts/setup.d/common/02-system-identity.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -f "${HOOK}" ] || fail "falta ${HOOK}"
bash -n "${HOOK}" || fail "syntax error en ${HOOK}"

run_branch() {
    local hwclock_local="$1" adjtime_out="$2"
    HWCLOCK_LOCAL="${hwclock_local}" bash -c '
        set -euo pipefail
        if [ "${HWCLOCK_LOCAL:-true}" = "true" ]; then
            printf "0.0 0 0.0\n0\nLOCAL\n"
        else
            printf "0.0 0 0.0\n0\nUTC\n"
        fi
    ' > "${adjtime_out}"
}

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

run_branch "true" "${tmp}"
grep -qx "LOCAL" "${tmp}" || fail "HWCLOCK_LOCAL=true debe dejar /etc/adjtime en LOCAL"

run_branch "false" "${tmp}"
grep -qx "UTC" "${tmp}" || fail "HWCLOCK_LOCAL=false debe dejar /etc/adjtime en UTC"

grep -q 'HWCLOCK_LOCAL' "${HOOK}" || fail "${HOOK} no lee HWCLOCK_LOCAL"
grep -q '/etc/adjtime' "${HOOK}" || fail "${HOOK} no escribe /etc/adjtime"

echo "PASS: hwclock local RTC"
