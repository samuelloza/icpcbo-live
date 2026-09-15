#!/usr/bin/env bash

set -euo pipefail

install -d -o root -g root -m 0755 /etc/contestiso
{
    printf 'AUTH_SERVICE_URL=%q\n' "${AUTH_SERVICE_URL}"
    printf 'AUTH_SERVICE_TIMEOUT=%q\n' "${AUTH_SERVICE_TIMEOUT}"
    printf 'TEAM_ID_REQUIRED=%q\n' "${TEAM_ID_REQUIRED}"
} > /etc/contestiso/auth.env
chown root:root /etc/contestiso/auth.env
chmod 0644 /etc/contestiso/auth.env
