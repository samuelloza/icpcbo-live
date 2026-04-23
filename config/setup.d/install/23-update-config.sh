#!/usr/bin/env bash

set -euo pipefail

install -d -m 0755 /etc/contestiso
{
    printf 'UPDATE_MANIFEST_URL=%q\n' "${UPDATE_MANIFEST_URL}"
    printf 'UPDATE_CHECK_ON_BOOT=%q\n' "${UPDATE_CHECK_ON_BOOT}"
    printf 'RUNTIME_VERSION=%q\n' "${RUNTIME_VERSION}"
} > /etc/contestiso/update.env
chmod 0644 /etc/contestiso/update.env
