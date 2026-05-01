#!/usr/bin/env bash

set -euo pipefail

# Lee los paquetes a eliminar línea por línea para evitar separación
# incorrecta de palabras dentro de la lista.
REMOVE_PKGS=()
while IFS= read -r pkg; do
    case "${pkg}" in
        ""|\#*)
            continue
            ;;
    esac
    REMOVE_PKGS+=("${pkg}")
done < /tmp/packages-remove.list

if [ "${#REMOVE_PKGS[@]}" -gt 0 ]; then
    apt-get purge -y "${REMOVE_PKGS[@]}" || true
fi

apt-get autoremove -y --purge || true

rm -f /etc/apt/apt.conf.d/01proxy || true

# /var/cache/apt/archives and /tmp/download-cache are host cache bind mounts

find /var/lib/apt/lists -mindepth 1 -exec rm -rf {} +
find /var/log -mindepth 1 -exec rm -rf {} +
find /tmp -mindepth 1 ! -name download-cache -exec rm -rf {} +
find /var/tmp -mindepth 1 -exec rm -rf {} +
