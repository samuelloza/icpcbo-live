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

# Install VSCode (always latest stable). The first pass may fail with unmet
# dependencies; apt-get -f install resolves them, then the second pass succeeds.
/tmp/cached-curl.sh "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" \
    /tmp/code.deb
apt-get install -y /tmp/code.deb || {
    apt-get -f install -y
    apt-get install -y /tmp/code.deb
}
rm -f /tmp/code.deb

/tmp/run-hook-dir.sh /tmp/setup.d

# Ensure the default user exists even if hooks are customized or disabled.
id -u "${DEFAULT_USER}" >/dev/null 2>&1 || \
    useradd -m -s /bin/bash -G sudo,audio,video "${DEFAULT_USER}"

# Propagate /etc/skel to the user home directory.
cp -a /etc/skel/. "/home/${DEFAULT_USER}/"
chown -R "${DEFAULT_USER}:${DEFAULT_USER}" "/home/${DEFAULT_USER}"
