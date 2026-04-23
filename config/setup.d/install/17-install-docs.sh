#!/usr/bin/env bash

set -euo pipefail
exit 0
CACHE_DIR="/tmp/cache"
mkdir -p "${CACHE_DIR}"

CPPREF_URL="https://github.com/PeterFeicht/cppreference-doc/releases/download/v20250209/html-book-20250209.zip"
CPPREF_ZIP="${CACHE_DIR}/html-book-20250209.zip"
CPPREF_DST="/usr/share/doc/cppreference"

if /tmp/cached-curl.sh "${CPPREF_URL}" "${CPPREF_ZIP}"; then
    mkdir -p "${CPPREF_DST}"
    unzip -o "${CPPREF_ZIP}" -d "${CPPREF_DST}" >/dev/null
else
    echo "W: failed downloading cppreference docs" >&2
fi
