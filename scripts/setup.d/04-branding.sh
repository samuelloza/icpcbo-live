#!/usr/bin/env bash

set -euo pipefail

META_DISTRO_ID_VAL="${META_DISTRO_ID:-icpc-bolivia-debian}"
META_DISTRO_NAME_VAL="${META_DISTRO_NAME:-ICPC Bolivia Debian}"
META_DISTRO_VERSION_VAL="${META_DISTRO_VERSION:-13}"

if [[ -f /etc/os-release ]]; then
    sed -i "s|^ID=.*|ID=${META_DISTRO_ID_VAL}|" /etc/os-release
    sed -i "s|^NAME=.*|NAME=\"${META_DISTRO_NAME_VAL}\"|" /etc/os-release
    sed -i "s|^PRETTY_NAME=.*|PRETTY_NAME=\"${META_DISTRO_NAME_VAL} ${META_DISTRO_VERSION_VAL}\"|" /etc/os-release
fi

if [[ -f /usr/lib/os-release ]]; then
    sed -i "s|^ID=.*|ID=${META_DISTRO_ID_VAL}|" /usr/lib/os-release
    sed -i "s|^NAME=.*|NAME=\"${META_DISTRO_NAME_VAL}\"|" /usr/lib/os-release
    sed -i "s|^PRETTY_NAME=.*|PRETTY_NAME=\"${META_DISTRO_NAME_VAL} ${META_DISTRO_VERSION_VAL}\"|" /usr/lib/os-release
fi

echo "${META_DISTRO_NAME_VAL} ${META_DISTRO_VERSION_VAL}" > /etc/issue
