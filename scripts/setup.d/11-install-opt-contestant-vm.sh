#!/usr/bin/env bash

set -euo pipefail

PROFILE_DIR="/tmp/contestant-vm"
ASSETS_DIR="/tmp/assets/contestant-vm"
DEST_DIR="${OPT_CONTEST_DIR:-/opt/icpc}"
LEGACY_DIR="/opt/contestant-vm"
DEFAULT_USER_VAL="${DEFAULT_USER:-icpc}"

mkdir -p "${DEST_DIR}"

if [ -d "${PROFILE_DIR}/files" ]; then
    cp -a "${PROFILE_DIR}/files/." "${DEST_DIR}/"
fi

if [ -d "${ASSETS_DIR}" ]; then
    cp -a "${ASSETS_DIR}/." "${DEST_DIR}/"
fi

mkdir -p "${DEST_DIR}/run"
mkdir -p "${DEST_DIR}/store/log"
mkdir -p "${DEST_DIR}/store/screenshots"
mkdir -p "${DEST_DIR}/store/submissions"
mkdir -p "${DEST_DIR}/config/ssh"

if [ -d "${DEST_DIR}/bin" ]; then
    find "${DEST_DIR}/bin" -type f -exec chmod 755 {} \;
fi
if [ -d "${DEST_DIR}/sbin" ]; then
    find "${DEST_DIR}/sbin" -type f -exec chmod 755 {} \;
fi

if [ "${DEST_DIR}" != "${LEGACY_DIR}" ]; then
    rm -rf "${LEGACY_DIR}"
    ln -s "${DEST_DIR}" "${LEGACY_DIR}"
fi

echo "${TIMEZONE:-America/La_Paz}" > "${DEST_DIR}/config/timezone"
touch "${DEST_DIR}/config/screenlock"

if id -u "${DEFAULT_USER_VAL}" >/dev/null 2>&1; then
    chown "${DEFAULT_USER_VAL}:${DEFAULT_USER_VAL}" "${DEST_DIR}/store/submissions" || true
fi
