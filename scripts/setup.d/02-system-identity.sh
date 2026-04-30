#!/usr/bin/env bash

set -euo pipefail

echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1 localhost
127.0.1.1 ${HOSTNAME}
::1 localhost ip6-localhost ip6-loopback
HOSTS

: > /etc/locale.gen
for locale in ${SUPPORTED_LOCALES}; do
    echo "${locale} UTF-8" >> /etc/locale.gen
done
locale-gen
update-locale LANG="${LOCALE}"

ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
echo "${TIMEZONE}" > /etc/timezone

# Distribución de teclado para consola y X11
# (leída por keyboard-setup.service durante el arranque)
cat > /etc/default/keyboard <<KEYBOARD_EOF
XKBMODEL="pc105"
XKBLAYOUT="${KEYBOARD_LAYOUT}"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
KEYBOARD_EOF
