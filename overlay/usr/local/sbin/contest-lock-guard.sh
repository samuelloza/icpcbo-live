#!/usr/bin/env bash
# Mientras exista /run/contest-locked, muestra un dialogo a pantalla completa.
# Con la clave de staff (lock.env) se puede desbloquear local si cae la red.
# Sin 'set -e': best-effort, que falle un zenity no debe tumbar el guardia.
set -uo pipefail

USER_NAME="${CONTEST_SESSION_USER:-icpc}"
LOCK_FLAG="${CONTEST_LOCK_FLAG:-/run/contest-locked}"
LOCK_ENV="${CONTEST_LOCK_ENV:-/etc/contestiso/lock.env}"
BINDING_ENV="${CONTEST_BINDING_ENV:-/etc/contestiso/binding.env}"

LOCKSCREEN_SALT=""
LOCKSCREEN_PASSWORD_SHA256=""
# shellcheck source=/dev/null
[ -r "${LOCK_ENV}" ] && . "${LOCK_ENV}"
TEAM_NAME=""; TEAM_SEAT=""
# shellcheck source=/dev/null
[ -r "${BINDING_ENV}" ] && . "${BINDING_ENV}"

# shellcheck source=/dev/null
. "${CONTEST_GUI_LIB:-/usr/local/lib/contest/gui.sh}"

msg="Esta maquina fue bloqueada por el coordinador."
[ -n "${TEAM_NAME}" ] && msg="${msg}\nEquipo: ${TEAM_NAME}${TEAM_SEAT:+  (asiento ${TEAM_SEAT})}"

while [ -e "${LOCK_FLAG}" ]; do
    if [ -n "${LOCKSCREEN_PASSWORD_SHA256}" ]; then
        pass="$(run_user zenity --password --title "MAQUINA BLOQUEADA" 2>/dev/null || true)"
        if [ -n "${pass}" ]; then
            got="$(printf '%s:%s' "${LOCKSCREEN_SALT}" "${pass}" | sha256sum | cut -d' ' -f1)"
            if [ "${got}" = "${LOCKSCREEN_PASSWORD_SHA256}" ]; then
                rm -f "${LOCK_FLAG}"
                logger -p local0.warn "ICPCBO-LOCK: desbloqueo local de emergencia" || true
                break
            fi
            run_user zenity --error --no-wrap --text "Clave incorrecta." >/dev/null 2>&1 || true
            continue
        fi
    fi
    run_user zenity --warning --no-wrap --title "MAQUINA BLOQUEADA" \
        --text "${msg}\nEspere instrucciones del coordinador." >/dev/null 2>&1 || true
    sleep 2
done
