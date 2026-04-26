#!/usr/bin/env bash

set -euo pipefail

HOSTNAME_VAL="${HOSTNAME:-contest}"
LOCALE_VAL="${LOCALE:-en_US.UTF-8}"
TIMEZONE_VAL="${TIMEZONE:-UTC}"
KEYBOARD_LAYOUT_VAL="${KEYBOARD_LAYOUT:-latam}"

echo "${HOSTNAME_VAL}" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1 localhost
127.0.1.1 ${HOSTNAME_VAL}
::1 localhost ip6-localhost ip6-loopback
HOSTS

grep -q "^${LOCALE_VAL}" /etc/locale.gen || echo "${LOCALE_VAL} UTF-8" >> /etc/locale.gen
locale-gen
update-locale LANG="${LOCALE_VAL}"

ln -sf "/usr/share/zoneinfo/${TIMEZONE_VAL}" /etc/localtime
echo "${TIMEZONE_VAL}" > /etc/timezone

# Keyboard layout for console and X11 (read by keyboard-setup.service at boot)
cat > /etc/default/keyboard <<KEYBOARD_EOF
XKBMODEL="pc105"
XKBLAYOUT="${KEYBOARD_LAYOUT_VAL}"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
KEYBOARD_EOF
