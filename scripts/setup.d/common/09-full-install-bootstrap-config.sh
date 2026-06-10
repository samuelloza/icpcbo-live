#!/usr/bin/env bash

set -euo pipefail

install -d -m 0755 /etc/contestiso
{
    printf 'FULL_INSTALL_URL=%q\n' "${FULL_INSTALL_URL}"
    printf 'FULL_INSTALL_SHA256=%q\n' "${FULL_INSTALL_SHA256}"
} > /etc/contestiso/full-install.env
chmod 0644 /etc/contestiso/full-install.env
