#!/usr/bin/env bash
# Reporta un evento al control-server. Uso: contest-alert.sh <kind> [detail]
set -euo pipefail

KIND="${1:?uso: contest-alert.sh <kind> [detail]}"
DETAIL="${2:-}"

ENV_FILE="${CONTEST_CONTROL_ENV:-/etc/contestiso/control.env}"
IDENT_FILE="${CONTEST_CONTROL_IDENTITY:-/etc/contestiso/identity.env}"
STATE_DIR="${CONTEST_CONTROL_STATE:-/var/lib/contest-control}"
MACHINE_ID_CMD="${CONTEST_MACHINE_ID_CMD:-/usr/local/bin/stats-machine-id.sh}"

CONTROL_SERVICE_URL=""
CONTROL_TIMEOUT="10"
# shellcheck source=/dev/null
[ -r "${ENV_FILE}" ] && . "${ENV_FILE}"
GROUP_ID=""
# shellcheck source=/dev/null
[ -r "${IDENT_FILE}" ] && . "${IDENT_FILE}"
CONTEST_USER_AGENT=""
# shellcheck source=/dev/null
[ -r "${CONTEST_HTTP_ENV:-/etc/contestiso/http.env}" ] && . "${CONTEST_HTTP_ENV:-/etc/contestiso/http.env}"
: "${CONTEST_USER_AGENT:=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36}"

[ -n "${CONTROL_SERVICE_URL}" ] && [ -n "${GROUP_ID}" ] || exit 0
[ -s "${STATE_DIR}/bearer" ] || exit 0
command -v curl >/dev/null 2>&1 || exit 0

MACHINE_ID="$("${MACHINE_ID_CMD}")"
BEARER="$(cat "${STATE_DIR}/bearer")"
BASE_URL="${CONTROL_SERVICE_URL%/}"

body="$(python3 -c 'import json,sys; print(json.dumps({"kind":sys.argv[1],"detail":sys.argv[2]}))' \
    "${KIND}" "${DETAIL}")"

curl --silent --show-error --max-time "${CONTROL_TIMEOUT}" -X POST -A "${CONTEST_USER_AGENT}" \
    -H "Authorization: Bearer ${BEARER}" -H "Content-Type: application/json" \
    -d "${body}" "${BASE_URL}/cmd/${GROUP_ID}/${MACHINE_ID}/events" >/dev/null 2>&1 || true
