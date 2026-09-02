#!/usr/bin/env bash

set -euo pipefail

CONFIG_FILE="/opt/icpc/misc/config"
STATE_FILE="/home/icpc/.local/state/icpcbo/team-id.txt"
WALLPAPER_FILE="/home/icpc/.local/state/icpcbo/login-wallpaper.svg"

DOSETUP=1

if [ -f "${CONFIG_FILE}" ]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
fi

if [ "${DOSETUP}" != "1" ]; then
    exit 0
fi

if [ ! -s "${STATE_FILE}" ]; then
    /opt/icpc/bin/contestants-login-xfce.sh || true
fi

if [ -s "${STATE_FILE}" ] && [ -f "${WALLPAPER_FILE}" ]; then
    while IFS= read -r property; do
        [ -n "${property}" ] || continue
        xfconf-query -c xfce4-desktop -p "${property}" -s "${WALLPAPER_FILE}" || true
    done < <(xfconf-query -c xfce4-desktop -l | grep "workspace0/last-image" || true)
fi
