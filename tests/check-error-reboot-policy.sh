#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INITRAMFS_LOCAL="${PROJECT_DIR}/overlay/etc/initramfs-tools/scripts/local"

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- Politica de errores de arranque ---------------------------------------
# En un error, la pantalla se detiene con una cuenta atras visible (default
# 60 s, contest.error_hold=) para que los encargados lean el mensaje; ENTER
# la corta. Luego se reinicia para reintentar. contest.error_hold=0 deja la
# pantalla detenida sin reiniciar.

grep -q '^hold_for_operator()' "${INITRAMFS_LOCAL}" \
    || fail "initramfs debe proveer hold_for_operator (cuenta atras + ENTER)"
grep -q 'CONTEST_ERROR_HOLD="60"' "${INITRAMFS_LOCAL}" \
    || fail "el hold por defecto debe ser 60 s"
grep -q 'contest.error_hold=\*)' "${INITRAMFS_LOCAL}" \
    || fail "contest.error_hold= debe ser configurable por cmdline"
grep -q 'stop_for_debug "RAM insuficiente:' "${INITRAMFS_LOCAL}" \
    || fail "el error de RAM baja debe pasar por el hold"
grep -q 'stop_for_debug "Error de instalacion persistente:' "${INITRAMFS_LOCAL}" \
    || fail "los errores de instalacion deben pasar por el hold"

# stop_for_debug: hold visible, luego reinicia (salvo error_hold=0).
awk '/^stop_for_debug\(\)/,/^}/' "${INITRAMFS_LOCAL}" > /tmp/.sfd.$$
grep -q 'hold_for_operator' /tmp/.sfd.$$ \
    || fail "stop_for_debug debe detener la pantalla con hold_for_operator"
grep -q 'force_reboot' /tmp/.sfd.$$ \
    || fail "stop_for_debug debe reiniciar tras el hold"
grep -qF 'CONTEST_ERROR_HOLD:-60}" = "0"' /tmp/.sfd.$$ \
    || fail "contest.error_hold=0 debe evitar el reinicio automatico"
rm -f /tmp/.sfd.$$

# --- Funcional: hold_for_operator en modo test ----------------------------
# shellcheck source=/dev/null
source "${INITRAMFS_LOCAL}"
CONTEST_TEST_NO_REBOOT="1"
unset CONTEST_TEST_HOLD_SECONDS
hold_for_operator 60
[[ "${CONTEST_TEST_HOLD_SECONDS:-}" = "60" ]] || fail "hold_for_operator no respeto los 60 s"
unset CONTEST_TEST_HOLD_SECONDS CONTEST_TEST_STOP_REASON
CONTEST_ERROR_HOLD="0" stop_for_debug "sin-reinicio" || true
[[ "${CONTEST_TEST_STOP_REASON:-}" = "sin-reinicio" ]] \
    || fail "con error_hold=0 stop_for_debug debe detenerse sin reiniciar (modo test)"
unset CONTEST_TEST_NO_REBOOT

echo "PASS: los errores de arranque detienen la pantalla 60 s (o hasta ENTER) y luego reintentan."
