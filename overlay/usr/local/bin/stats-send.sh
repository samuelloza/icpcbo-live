#!/usr/bin/env bash

set -euo pipefail

TIMEOUT="10"
ICP_REPORT_URL=""

if [[ -f /etc/contestiso/auth.env ]]; then
    # shellcheck source=/dev/null
    source /etc/contestiso/auth.env
fi

TIMEOUT="${ICP_REPORT_TIMEOUT:-${TIMEOUT}}"

: "${ICP_REPORT_URL:?ICP_REPORT_URL is required}"

mkdir -p /var/lib/statsbo/pending

DATA_FILE="$(mktemp)"
LOGS_FILE="$(mktemp)"
METRICS_FILE="$(mktemp)"
HARDWARE_FILE="$(mktemp)"

cleanup() {
    rm -f "${LOGS_FILE}" "${METRICS_FILE}" "${HARDWARE_FILE}"
}
trap cleanup EXIT

/usr/local/bin/stats-logs.sh > "${LOGS_FILE}"
/usr/local/bin/stats-metrics.sh > "${METRICS_FILE}"
/usr/local/bin/stats-hardware.sh > "${HARDWARE_FILE}"

/usr/local/bin/stats-build-payload.py \
    "$(/usr/local/bin/stats-machine-id.sh)" \
    "${LOGS_FILE}" \
    "${METRICS_FILE}" \
    "${HARDWARE_FILE}" \
    "/home/icpc/.local/state/icpcbo" > "${DATA_FILE}"

if ! curl --fail --silent --show-error --max-time "${TIMEOUT}" \
    -X POST -H "Content-Type: application/json" \
    -d @"${DATA_FILE}" "${ICP_REPORT_URL}"; then
    mv "${DATA_FILE}" "/var/lib/statsbo/pending/$(date +%s).json"
else
    rm -f "${DATA_FILE}"
fi

for f in /var/lib/statsbo/pending/*.json; do
    [[ ! -f "${f}" ]] && continue
    if curl --fail --silent --show-error --max-time "${TIMEOUT}" \
        -X POST -H "Content-Type: application/json" \
        -d @"${f}" "${ICP_REPORT_URL}"; then
        rm -f "${f}"
    fi
done
