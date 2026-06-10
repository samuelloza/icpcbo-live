#!/usr/bin/env bash

set -euo pipefail

install -d -m 0755 /etc/contestiso
{
    printf 'UPDATE_MANIFEST_URL=%q\n' "${UPDATE_MANIFEST_URL}"
    printf 'UPDATE_CHECK_ON_BOOT=%q\n' "${UPDATE_CHECK_ON_BOOT}"
    printf 'RUNTIME_VERSION=%q\n' "${RUNTIME_VERSION}"
} > /etc/contestiso/update.env
chmod 0644 /etc/contestiso/update.env

{
    printf 'AUTH_SERVICE_URL=%q\n' "${AUTH_SERVICE_URL}"
    printf 'AUTH_SERVICE_TIMEOUT=%q\n' "${AUTH_SERVICE_TIMEOUT}"
} > /etc/contestiso/auth.env
chmod 0644 /etc/contestiso/auth.env

{
    printf 'ICP_REPORT_URL=%q\n' "${ICP_REPORT_URL}"
    printf 'ICP_REPORT_TIMEOUT=%q\n' "${ICP_REPORT_TIMEOUT}"
    printf 'STATS_LOG_SINCE=%q\n' "${STATS_LOG_SINCE}"
    printf 'STATS_REPORT_ON_BOOT=%q\n' "${STATS_REPORT_ON_BOOT}"
    printf 'STATS_REPORT_INTERVAL=%q\n' "${STATS_REPORT_INTERVAL}"
} > /etc/contestiso/stats.env
chmod 0644 /etc/contestiso/stats.env
