#!/usr/bin/env bash
# Fase cacheable: solo debootstrap ya está hecho; aquí se instalan los paquetes
# del perfil. El resultado (rootfs base) solo depende de packages.list + suite,
# así que build.sh lo cachea como tarball y salta esta fase si nada cambió.
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
        ""|\#*) continue ;;
    esac
    add_package_if_available "${pkg}"
done < /tmp/packages.list

if [ "${#PKGS[@]}" -gt 0 ]; then
    apt-get install -y "${PKGS[@]}"
fi
