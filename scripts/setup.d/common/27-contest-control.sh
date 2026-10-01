#!/usr/bin/env bash
# Config + identidad + clave de bloqueo para el cliente de control remoto.
set -euo pipefail

install -d -o root -g root -m 0755 /etc/contestiso
for s in contest-control.sh contest-session.sh contest-lock-guard.sh \
         contest-freeze-guard.sh contest-set-wallpaper.sh contest-reset-home.sh \
         contest-alert.sh contest-net.sh contest-screenshot.sh contest-call-staff-drain.sh \
         contest-set-homepage.sh; do
    chmod 0755 "/usr/local/sbin/${s}"
done

{
    printf 'CONTROL_SERVICE_URL=%q\n' "${CONTROL_SERVICE_URL:-}"
    printf 'CONTROL_TIMEOUT=%q\n' "${CONTROL_TIMEOUT:-20}"
    printf 'CONTROL_LONGPOLL_WAIT=%q\n' "${CONTROL_LONGPOLL_WAIT:-25}"
    printf 'CONTROL_STATUS_EVERY=%q\n' "${CONTROL_STATUS_EVERY:-1}"
    printf 'CONTROL_JOURNAL_EVERY=%q\n' "${CONTROL_JOURNAL_EVERY:-20}"
    printf 'ALLOW_VM=%q\n' "${ALLOW_VM:-false}"
    printf 'DEFAULT_USER=%q\n' "${DEFAULT_USER}"
} > /etc/contestiso/control.env
chmod 0644 /etc/contestiso/control.env

# Identidad por sede (valores reales en config/iso.local.conf).
umask 077
{
    printf 'GROUP_ID=%q\n' "${GROUP_ID:-}"
    printf 'ENROLL_TOKEN=%q\n' "${ENROLL_TOKEN:-}"
} > /etc/contestiso/identity.env
umask 022
chmod 0600 /etc/contestiso/identity.env

# Clave de desbloqueo local de emergencia: se hornea solo el hash salado, nunca
# el texto plano.
umask 077
if [ -n "${LOCKSCREEN_PASSWORD:-}" ]; then
    salt="$(head -c 12 /dev/urandom | base64)"
    hash="$(printf '%s:%s' "${salt}" "${LOCKSCREEN_PASSWORD}" | sha256sum | cut -d' ' -f1)"
    {
        printf 'LOCKSCREEN_SALT=%q\n' "${salt}"
        printf 'LOCKSCREEN_PASSWORD_SHA256=%q\n' "${hash}"
    } > /etc/contestiso/lock.env
else
    : > /etc/contestiso/lock.env
fi
umask 022
chmod 0600 /etc/contestiso/lock.env

systemctl enable contest-reset-home.service

if [ -z "${CONTROL_SERVICE_URL:-}" ]; then
    echo "CONTROL_SERVICE_URL vacio: control remoto no se activa"
    exit 0
fi

systemctl enable contest-control.service
