#!/usr/bin/env bash

set -euo pipefail

PROFILE_DIR="/tmp/contestant-vm"
DEST_DIR="/opt/contestant-vm"
DEFAULT_USER_VAL="${DEFAULT_USER:-icpc}"

[ -d "${PROFILE_DIR}/files" ] || exit 0

mkdir -p "${DEST_DIR}"
cp -a "${PROFILE_DIR}/files/." "${DEST_DIR}/"

mkdir -p "${DEST_DIR}/run"
mkdir -p "${DEST_DIR}/store/log"
mkdir -p "${DEST_DIR}/store/screenshots"
mkdir -p "${DEST_DIR}/store/submissions"
mkdir -p "${DEST_DIR}/config/ssh"

echo "${TIMEZONE:-America/La_Paz}" > "${DEST_DIR}/config/timezone"
touch "${DEST_DIR}/config/screenlock"

if id -u "${DEFAULT_USER_VAL}" >/dev/null 2>&1; then
    chown "${DEFAULT_USER_VAL}:${DEFAULT_USER_VAL}" "${DEST_DIR}/store/submissions" || true
fi
