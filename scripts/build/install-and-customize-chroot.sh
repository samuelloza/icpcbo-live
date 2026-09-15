#!/usr/bin/env bash
# Personalización del rootfs: hooks de setup.d + usuario por defecto + skel.
# La instalación de paquetes se hace antes, en install-packages-chroot.sh (fase
# cacheable). build.sh garantiza que los paquetes ya están en el rootfs cuando
# se llega aquí (recién instalados o restaurados del tarball base).
set -euo pipefail

/tmp/run-hook-dir.sh /tmp/setup.d

# Asegura que el usuario por defecto exista incluso si los hooks fueron
# personalizados o deshabilitados. Nunca en 'sudo'.
id -u "${DEFAULT_USER}" >/dev/null 2>&1 || \
    useradd -m -s /bin/bash -G audio,video "${DEFAULT_USER}"

# Copia el contenido de /etc/skel al directorio personal del usuario.
cp -a /etc/skel/. "/home/${DEFAULT_USER}/"
chown -R "${DEFAULT_USER}:${DEFAULT_USER}" "/home/${DEFAULT_USER}"

# Endurecimiento final (corre siempre, después de todos los hooks): el usuario
# del concurso jamás en 'sudo', y root sin login salvo que ROOT_PASSWORD esté
# definido en config/iso.local.conf. El recovery normal es por GRUB (con
# contraseña). Necesario para que el bloqueo de red (nftables) no sea evitable.
#
# DEBUG_SUDO=true (solo en config/iso.local.conf, builds de depuración): deja al
# usuario del concurso EN 'sudo' (contraseña = DEFAULT_PASSWORD). NUNCA en
# producción: con sudo el bloqueo de red es evitable.
if [[ "${DEBUG_SUDO:-false}" == "true" ]]; then
    getent group sudo >/dev/null 2>&1 && usermod -aG sudo "${DEFAULT_USER}"
    echo "  ###### DEBUG_SUDO=true: ${DEFAULT_USER} TIENE sudo (pass ${DEFAULT_PASSWORD:-?}) ######" >&2
elif getent group sudo >/dev/null 2>&1; then
    gpasswd -d "${DEFAULT_USER}" sudo 2>/dev/null || true
fi
if [[ -n "${ROOT_PASSWORD:-}" ]]; then
    echo "root:${ROOT_PASSWORD}" | chpasswd
else
    passwd -l root
fi
