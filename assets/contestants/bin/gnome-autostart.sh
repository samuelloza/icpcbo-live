#!/usr/bin/env bash

set -euo pipefail

CONFIG_FILE="/opt/icpc/misc/config"
STATE_DIR="${CONTEST_LOGIN_STATE_DIR:-${XDG_STATE_HOME:-${HOME}/.local/state}/icpcbo}"
STATE_FILE="${STATE_DIR}/team-id.txt"
WALLPAPER_FILE="${STATE_DIR}/login-wallpaper.svg"

DOSETUP=1

if [ -f "${CONFIG_FILE}" ]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
fi

if [ "${DOSETUP}" != "1" ]; then
    exit 0
fi

if [ ! -s "${STATE_FILE}" ]; then
    /opt/icpc/bin/contestants-login-gnome.sh || true
fi

if [ -s "${STATE_FILE}" ] && [ -f "${WALLPAPER_FILE}" ]; then
    gsettings set org.gnome.desktop.background picture-uri "file://${WALLPAPER_FILE}"
    gsettings set org.gnome.desktop.background picture-uri-dark "file://${WALLPAPER_FILE}"
fi
