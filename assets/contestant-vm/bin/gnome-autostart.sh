#!/usr/bin/env bash

set -euo pipefail

CONFIG_FILE="/opt/icpc/misc/config"
STATE_FILE="${XDG_STATE_HOME:-${HOME}/.local/state}/icpcbo/user-id.txt"
DOSETUP=1

if [ -f "${CONFIG_FILE}" ]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
fi

if [ "${DOSETUP}" != "1" ]; then
    exit 0
fi

if [ ! -s "${STATE_FILE}" ]; then
    /opt/icpc/bin/icpcbo-login.sh || true
fi
