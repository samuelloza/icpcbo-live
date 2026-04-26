#!/usr/bin/env bash

set -euo pipefail

DEFAULT_USER_VAL="${DEFAULT_USER:-icpc}"
DEFAULT_PASSWORD_VAL="${DEFAULT_PASSWORD:-icpc}"
ENABLE_AUTOLOGIN_VAL="${ENABLE_AUTOLOGIN:-false}"

if ! id -u "${DEFAULT_USER_VAL}" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "${DEFAULT_USER_VAL}"
fi

for group in sudo audio video; do
    if getent group "${group}" >/dev/null 2>&1; then
        usermod -aG "${group}" "${DEFAULT_USER_VAL}"
    fi
done

echo "${DEFAULT_USER_VAL}:${DEFAULT_PASSWORD_VAL}" | chpasswd
echo "root:${DEFAULT_PASSWORD_VAL}" | chpasswd

if [[ "${ENABLE_AUTOLOGIN_VAL}" == "true" ]]; then
    mkdir -p /etc/gdm3
    cat > /etc/gdm3/custom.conf <<GDM
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=${DEFAULT_USER_VAL}
GDM
fi
