#!/usr/bin/env bash
# Captura pantalla del usuario del concurso, sin sonido ni flash. Uso:
# contest-screenshot.sh <salida.png>

set -euo pipefail

OUT="${1:?uso: contest-screenshot.sh <salida.png>}"
# shellcheck source=/dev/null
. "${CONTEST_GUI_LIB:-/usr/local/lib/contest/gui.sh}"

user_tmp="/run/user/$(id -u "${CONTEST_SESSION_USER:-icpc}")/.contest-shot.png"

run_user sh -c '
    rm -f "$1"
    gdbus call --session --dest org.gnome.Shell.Screenshot \
        --object-path /org/gnome/Shell/Screenshot \
        --method org.gnome.Shell.Screenshot.Screenshot true false "$1" >/dev/null 2>&1
    [ -s "$1" ] || { command -v xfce4-screenshooter >/dev/null 2>&1 && \
        xfce4-screenshooter -f -s "$1" >/dev/null 2>&1; }
    [ -s "$1" ] || { command -v gnome-screenshot >/dev/null 2>&1 && \
        gnome-screenshot -f "$1" >/dev/null 2>&1; }
    [ -s "$1" ]
' _ "${user_tmp}" || { echo "captura vacia/fallida" >&2; exit 1; }

cat "${user_tmp}" > "${OUT}"
run_user rm -f "${user_tmp}" 2>/dev/null || true
