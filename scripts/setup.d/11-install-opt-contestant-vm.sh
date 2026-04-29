#!/usr/bin/env bash

set -euo pipefail

PROFILE_DIR="/tmp/contestant-vm"
ASSETS_DIR="/tmp/assets/contestant-vm"
DEST_DIR="${OPT_CONTEST_DIR:-/opt/icpc}"
DEFAULT_USER_VAL="${DEFAULT_USER:-icpc}"

mkdir -p "${DEST_DIR}"

if [ -d "${PROFILE_DIR}/files" ]; then
    cp -a "${PROFILE_DIR}/files/." "${DEST_DIR}/"
fi

if [ -d "${ASSETS_DIR}" ]; then
    cp -a "${ASSETS_DIR}/." "${DEST_DIR}/"
fi

mkdir -p "${DEST_DIR}/run"

if [ -d "${DEST_DIR}/bin" ]; then
    find "${DEST_DIR}/bin" -type f -exec chmod 755 {} \;
fi
if [ -d "${DEST_DIR}/sbin" ]; then
    find "${DEST_DIR}/sbin" -type f -exec chmod 755 {} \;
fi
