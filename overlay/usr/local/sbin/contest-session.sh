#!/usr/bin/env bash
# lock / unlock / message sobre la sesion grafica. Se llama como root.
set -euo pipefail

# OJO: NO usar ${1:?...{...}...} — bash cierra el ${} en la primera '}' del
# mensaje y deja una '}' literal pegada a $1 (ACTION queda "lock}", etc.).
ACTION="${1:-}"
[ -n "${ACTION}" ] || { echo "uso: contest-session.sh lock|unlock|message <texto>|logout" >&2; exit 2; }
USER_NAME="${CONTEST_SESSION_USER:-icpc}"
LOCK_FLAG="${CONTEST_LOCK_FLAG:-/run/contest-locked}"

# shellcheck source=/dev/null
. "${CONTEST_GUI_LIB:-/usr/local/lib/contest/gui.sh}"

case "${ACTION}" in
    lock)
        # Bloqueo best-effort. El guardia repone un zenity a pantalla
        # completa cada 2 s; un kiosk real pararia el display-manager.
        : > "${LOCK_FLAG}"
        loginctl lock-sessions 2>/dev/null || true
        systemctl start contest-lock-guard.service 2>/dev/null || true
        ;;
    unlock)
        rm -f "${LOCK_FLAG}"
        systemctl stop contest-lock-guard.service 2>/dev/null || true
        loginctl unlock-sessions 2>/dev/null || true
        ;;
    message)
        shift
        text="${1:-Mensaje del coordinador}"
        # La notificacion D-Bus es el criterio de exito (llega siempre, tambien
        # con la pantalla bloqueada). El dialogo zenity es un extra mas visible.
        notify_user "${text}" "Coordinador ICPC" || exit 1
        run_user zenity --info --no-wrap --title "ICPC Bolivia" \
            --text "${text}" >/dev/null 2>&1 &
        ;;
    logout)
        # Borra el estado de login (team-id.txt, etc.) y termina la sesion:
        # al reiniciarla, el autostart la encuentra vacia y vuelve a pedir
        # credenciales (ver gnome-autostart.sh / xfce-autostart.sh).
        rm -rf "/home/${USER_NAME}/.local/state/icpcbo"
        loginctl terminate-user "${USER_NAME}" 2>/dev/null || true
        ;;
    *)
        echo "accion invalida: ${ACTION}" >&2
        exit 2
        ;;
esac
