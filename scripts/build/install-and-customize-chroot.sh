#!/usr/bin/env bash
# Personalización del rootfs: hooks de setup.d + usuario por defecto + skel.
# La instalación de paquetes se hace antes, en install-packages-chroot.sh (fase
# cacheable). build.sh garantiza que los paquetes ya están en el rootfs cuando
# se llega aquí (recién instalados o restaurados del tarball base).
set -euo pipefail

/tmp/run-hook-dir.sh /tmp/setup.d

# Asegura que el usuario por defecto exista incluso si los hooks fueron
# personalizados o deshabilitados.
id -u "${DEFAULT_USER}" >/dev/null 2>&1 || \
    useradd -m -s /bin/bash -G sudo,audio,video "${DEFAULT_USER}"

# Copia el contenido de /etc/skel al directorio personal del usuario.
cp -a /etc/skel/. "/home/${DEFAULT_USER}/"
chown -R "${DEFAULT_USER}:${DEFAULT_USER}" "/home/${DEFAULT_USER}"
