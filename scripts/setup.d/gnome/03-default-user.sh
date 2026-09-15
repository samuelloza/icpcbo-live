#!/usr/bin/env bash

set -euo pipefail

if ! id -u "${DEFAULT_USER}" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "${DEFAULT_USER}"
fi

desktop_groups=()
for group in audio video; do
    if getent group "${group}" >/dev/null 2>&1; then
        desktop_groups+=("${group}")
    fi
done
if (( ${#desktop_groups[@]} )); then
    usermod -G "$(IFS=,; echo "${desktop_groups[*]}")" "${DEFAULT_USER}"
fi

# Solo la cuenta del concurso (respaldo manual del staff si el autologin falla).
# root lo maneja install-and-customize-chroot.sh: bloqueado salvo ROOT_PASSWORD.
if [[ -n "${DEFAULT_PASSWORD:-}" ]]; then
    echo "${DEFAULT_USER}:${DEFAULT_PASSWORD}" | chpasswd
fi

if [[ "${ENABLE_AUTOLOGIN}" == "true" ]]; then
    etc_dir="${ETC_DIR:-/etc}"
    mkdir -p "${etc_dir}/gdm3"
    # Debian gdm3 lee daemon.conf; Ubuntu lee custom.conf. Se escriben ambos.
    for conf in daemon.conf custom.conf; do
        cat > "${etc_dir}/gdm3/${conf}" <<GDM
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=${DEFAULT_USER}
GDM
    done
fi
