#!/usr/bin/env bash
# Limpia /home del usuario del concurso y lo deja como /etc/skel.
# --now: lo hace ya, sin reboot (cierra sesion y reinicia el display-manager).
# Sin args: solo corre si existe el marcador (arranque via .service).
set -euo pipefail

FLAG="${CONTEST_RESET_HOME_FLAG:-/var/lib/contest-control/reset-home}"
USER_NAME="${CONTEST_RESET_HOME_USER:-icpc}"
NOW=0
[ "${1:-}" = "--now" ] && NOW=1

home="/home/${USER_NAME}"
[ -n "${home}" ] && [ "${home}" != "/" ] || { echo "home invalido" >&2; exit 1; }

if [ "${NOW}" = 1 ]; then
    echo "[contest-reset-home] cerrando la sesion de ${USER_NAME}..."
    loginctl terminate-user "${USER_NAME}" 2>/dev/null || true
    sleep 1
    pkill -KILL -u "${USER_NAME}" 2>/dev/null || true
    sleep 1
else
    [ -e "${FLAG}" ] || exit 0
fi

echo "[contest-reset-home] limpiando ${home}"
find "${home}" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
cp -a /etc/skel/. "${home}/"
chown -R "${USER_NAME}:${USER_NAME}" "${home}"
rm -f "${FLAG}"

if [ "${NOW}" = 1 ]; then
    echo "[contest-reset-home] reiniciando el escritorio (autologin)..."
    sync
    systemctl restart display-manager.service 2>/dev/null || true
fi
