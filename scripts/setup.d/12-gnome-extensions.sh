#!/usr/bin/env bash

set -euo pipefail

PROFILE_DIR="/tmp/contestant-vm"
EXT_SRC="${PROFILE_DIR}/files/misc"
LOCAL_EXT_SRC="/tmp/assets/gnome-extensions"
EXT_DST="/usr/share/gnome-shell/extensions"

mkdir -p "${EXT_DST}"

for ext in stealmyfocus-ext; do
    installed=0

    if [ -d "${EXT_SRC}/${ext}" ]; then
        rm -rf "${EXT_DST:?}/${ext}"
        cp -a "${EXT_SRC}/${ext}" "${EXT_DST}/"
        installed=1
    fi

    if [ -d "${LOCAL_EXT_SRC}/${ext}" ]; then
        rm -rf "${EXT_DST:?}/${ext}"
        cp -a "${LOCAL_EXT_SRC}/${ext}" "${EXT_DST}/"
        installed=1
    fi

    if [ "${installed}" -eq 1 ]; then
        find "${EXT_DST}/${ext}" -type f -exec chmod 644 {} \;
        find "${EXT_DST}/${ext}" -type d -exec chmod 755 {} \;
        echo "I: installed GNOME extension: ${ext}"
    else
        echo "W: extension not found: ${EXT_SRC}/${ext}" >&2
    fi
done
