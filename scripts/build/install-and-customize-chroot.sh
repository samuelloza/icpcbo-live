#!/usr/bin/env bash

set -euo pipefail

apt-get update

add_package_if_available() {
    local pkg="$1"
    local candidate

    candidate="$(apt-cache policy "${pkg}" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
    if [ -n "${candidate}" ] && [ "${candidate}" != "(none)" ]; then
        PKGS+=("${pkg}")
        return 0
    fi

    echo "W: package not found in repo, skipping: ${pkg}" >&2
}

PKGS=()
while IFS= read -r pkg; do
    case "${pkg}" in
        ""|\#*)
            continue
            ;;
    esac
    add_package_if_available "${pkg}"
done < /tmp/packages.list

if [ "${#PKGS[@]}" -gt 0 ]; then
    apt-get install -y "${PKGS[@]}"
fi

/tmp/run-hook-dir.sh /tmp/setup.d

# Asegura que el usuario por defecto exista incluso si los hooks fueron
# personalizados o deshabilitados.
id -u "${DEFAULT_USER}" >/dev/null 2>&1 || \
    useradd -m -s /bin/bash -G sudo,audio,video "${DEFAULT_USER}"

# Copia el contenido de /etc/skel al directorio personal del usuario.
cp -a /etc/skel/. "/home/${DEFAULT_USER}/"
chown -R "${DEFAULT_USER}:${DEFAULT_USER}" "/home/${DEFAULT_USER}"
