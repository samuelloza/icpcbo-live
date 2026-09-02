#!/usr/bin/env bash

set -euo pipefail

if ! id -u "${DEFAULT_USER}" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "${DEFAULT_USER}"
fi

desktop_groups=()
for group in audio video netdev plugdev; do
    if getent group "${group}" >/dev/null 2>&1; then
        desktop_groups+=("${group}")
    fi
done
if (( ${#desktop_groups[@]} )); then
    usermod -G "$(IFS=,; echo "${desktop_groups[*]}")" "${DEFAULT_USER}"
fi

if [[ -n "${DEFAULT_PASSWORD:-}" ]]; then
    echo "${DEFAULT_USER}:${DEFAULT_PASSWORD}" | chpasswd
    echo "root:${DEFAULT_PASSWORD}" | chpasswd
fi

if [[ "${ENABLE_AUTOLOGIN}" == "true" ]]; then
    etc_dir="${ETC_DIR:-/etc}"
    mkdir -p "${etc_dir}/lightdm/lightdm.conf.d"
    cat > "${etc_dir}/lightdm/lightdm.conf.d/50-icpc-autologin.conf" <<LIGHTDM
[Seat:*]
autologin-user=${DEFAULT_USER}
autologin-user-timeout=0
user-session=xfce
LIGHTDM
fi
