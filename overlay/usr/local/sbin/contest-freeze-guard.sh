#!/usr/bin/env bash
# Modo 'donottouch': bloqueo duro del que el concursante no puede salir solo.
# Invalida la contraseña (passwd -l) asi no se desbloquea escribiendola, y
# re-bloquea la sesion cada pocos segundos. Solo cantouch (passwd -u) lo saca.
# Sin 'set -e': un gsettings/loginctl/passwd fallido no debe tumbar el guardia.
set -uo pipefail

FROZEN_FLAG="${CONTEST_FROZEN_FLAG:-/var/lib/contest-control/frozen}"
FREEZE_WP="${CONTEST_FREEZE_WALLPAPER:-/opt/icpc/misc/freeze-wallpaper.svg}"
SAVED_FILE="${CONTEST_FREEZE_SAVED:-/run/contest-freeze-wallpaper}"
PWLOCK_MARK="${CONTEST_FREEZE_PWLOCK:-/run/contest-freeze-pwlock}"
USER_NAME="${CONTEST_SESSION_USER:-icpc}"

# shellcheck source=/dev/null
. "${CONTEST_GUI_LIB:-/usr/local/lib/contest/gui.sh}"

_get_wp() { run_user gsettings get org.gnome.desktop.background picture-uri 2>/dev/null; }
_set_wp() {
    local sch
    for sch in org.gnome.desktop.background org.gnome.desktop.screensaver; do
        run_user gsettings set "${sch}" picture-uri "$1"      2>/dev/null || true
        run_user gsettings set "${sch}" picture-uri-dark "$1" 2>/dev/null || true
    done
    run_user gsettings set org.gnome.desktop.background picture-options 'zoom' 2>/dev/null || true
}

# Fondo a restaurar: el de un arranque previo si quedo guardado, o el actual.
if [ -s "${SAVED_FILE}" ]; then
    SAVED="$(cat "${SAVED_FILE}")"
else
    SAVED="$(_get_wp)"; [ -n "${SAVED}" ] || SAVED="''"
    printf '%s\n' "${SAVED}" > "${SAVED_FILE}" 2>/dev/null || true
fi

restore() {
    if [ -e "${PWLOCK_MARK}" ]; then
        passwd -u "${USER_NAME}" >/dev/null 2>&1 || true
        rm -f "${PWLOCK_MARK}"
    fi
    loginctl unlock-sessions 2>/dev/null || true
    _set_wp "${SAVED}"
    rm -f "${SAVED_FILE}"
}
trap restore EXIT

[ -f "${FREEZE_WP}" ] && _set_wp "file://${FREEZE_WP}"
# Invalida la contraseña solo si tiene una usable (evita dejar la cuenta sin
# contraseña al restaurar). Marca que fuimos nosotros los que la bloqueamos.
if passwd -S "${USER_NAME}" 2>/dev/null | grep -q ' P '; then
    passwd -l "${USER_NAME}" >/dev/null 2>&1 && : > "${PWLOCK_MARK}"
fi
loginctl lock-sessions 2>/dev/null || true

while [ -e "${FROZEN_FLAG}" ]; do
    loginctl lock-sessions 2>/dev/null || true
    sleep 3
done
