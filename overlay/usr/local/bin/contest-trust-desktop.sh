#!/bin/sh
# desktop-icons-ng no lanza un .desktop del escritorio (lo marca "archivo roto"
# o "no confiable") si no tiene el bit +x y el atributo metadata::trusted.
# Se corre en cada login: /home se limpia con reset-home y borra el metadata,
# hay que reponerlo. Idempotente.
set -eu

desktop="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
[ -d "${desktop}" ] || exit 0

for f in "${desktop}"/*.desktop; do
    [ -e "${f}" ] || continue
    chmod +x "${f}" 2>/dev/null || true
    gio set "${f}" metadata::trusted true 2>/dev/null || true
done
