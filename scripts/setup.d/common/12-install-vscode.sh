#!/usr/bin/env bash

set -euo pipefail

VSCODE_VERSION="${VSCODE_VERSION:-1.96.4}"

/tmp/cached-curl.sh \
    "https://update.code.visualstudio.com/${VSCODE_VERSION}/linux-deb-x64/stable" \
    /tmp/code.deb

echo 'code code/add-microsoft-repo boolean false' | debconf-set-selections

apt-get install -y /tmp/code.deb || {
    apt-get -f install -y
    apt-get install -y /tmp/code.deb
}

rm -f /tmp/code.deb \
    /etc/apt/sources.list.d/vscode*.list \
    /etc/apt/sources.list.d/vscode*.sources \
    /etc/apt/sources.list.d/microsoft*.list \
    /etc/apt/sources.list.d/microsoft*.sources \
    /usr/share/keyrings/microsoft*.gpg \
    /etc/apt/trusted.gpg.d/microsoft*.gpg

# El repo también puede quedar apuntado desde el sources.list principal.
sed -i '\#packages.microsoft.com/repos/code#d' /etc/apt/sources.list 2>/dev/null || true
