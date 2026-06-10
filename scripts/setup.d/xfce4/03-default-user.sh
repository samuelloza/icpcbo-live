#!/usr/bin/env bash

set -euo pipefail

if ! id -u "${DEFAULT_USER}" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "${DEFAULT_USER}"
fi

for group in sudo audio video netdev plugdev; do
    if getent group "${group}" >/dev/null 2>&1; then
        usermod -aG "${group}" "${DEFAULT_USER}"
    fi
done

echo "${DEFAULT_USER}:${DEFAULT_PASSWORD}" | chpasswd
echo "root:${DEFAULT_PASSWORD}" | chpasswd

if [[ "${ENABLE_AUTOLOGIN}" == "true" ]]; then
    mkdir -p /etc/lightdm/lightdm.conf.d
    cat > /etc/lightdm/lightdm.conf.d/50-icpc-autologin.conf <<LIGHTDM
[Seat:*]
autologin-user=${DEFAULT_USER}
autologin-user-timeout=0
user-session=xfce
LIGHTDM
fi
