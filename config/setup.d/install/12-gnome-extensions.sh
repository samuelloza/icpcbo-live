#!/usr/bin/env bash

set -euo pipefail
exit 0
PROFILE_DIR="/tmp/contestant-vm"
EXT_SRC="${PROFILE_DIR}/files/misc"
EXT_DST="/usr/share/gnome-shell/extensions"

mkdir -p "${EXT_DST}"

for ext in stealmyfocus-ext; do
    if [ -d "${EXT_SRC}/${ext}" ]; then
        cp -a "${EXT_SRC}/${ext}" "${EXT_DST}/"
        find "${EXT_DST}/${ext}" -type f -exec chmod 644 {} \;
        find "${EXT_DST}/${ext}" -type d -exec chmod 755 {} \;
        echo "I: installed GNOME extension: ${ext}"
    else
        echo "W: extension not found: ${EXT_SRC}/${ext}" >&2
    fi
done
