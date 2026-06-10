#!/usr/bin/env bash

set -euo pipefail

if [[ -f /etc/os-release ]]; then
    sed -i "s|^ID=.*|ID=${META_DISTRO_ID}|" /etc/os-release
    sed -i "s|^NAME=.*|NAME=\"${META_DISTRO_NAME}\"|" /etc/os-release
    sed -i "s|^PRETTY_NAME=.*|PRETTY_NAME=\"${META_DISTRO_NAME} ${META_DISTRO_VERSION}\"|" /etc/os-release
fi

if [[ -f /usr/lib/os-release ]]; then
    sed -i "s|^ID=.*|ID=${META_DISTRO_ID}|" /usr/lib/os-release
    sed -i "s|^NAME=.*|NAME=\"${META_DISTRO_NAME}\"|" /usr/lib/os-release
    sed -i "s|^PRETTY_NAME=.*|PRETTY_NAME=\"${META_DISTRO_NAME} ${META_DISTRO_VERSION}\"|" /usr/lib/os-release
fi

echo "${META_DISTRO_NAME} ${META_DISTRO_VERSION}" > /etc/issue
