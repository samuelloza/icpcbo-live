#!/usr/bin/env bash

set -euo pipefail

CACHE_DIR="/tmp/cache"
mkdir -p "${CACHE_DIR}"

CPPREF_URL="https://github.com/PeterFeicht/cppreference-doc/releases/download/v20250209/html-book-20250209.zip"
CPPREF_ZIP="${CACHE_DIR}/html-book-20250209.zip"
CPPREF_DST="/usr/share/doc/cppreference"
ICPCBO_DOC_DST="/usr/share/doc/icpcbo"

if /tmp/cached-curl.sh "${CPPREF_URL}" "${CPPREF_ZIP}"; then
    mkdir -p "${CPPREF_DST}"
    unzip -o "${CPPREF_ZIP}" -d "${CPPREF_DST}" >/dev/null
else
    echo "W: failed downloading cppreference docs" >&2
fi

mkdir -p "${ICPCBO_DOC_DST}"

if [ -d "${CPPREF_DST}/reference/en" ]; then
    ln -sfn "${CPPREF_DST}/reference/en" "${ICPCBO_DOC_DST}/cppreference"
fi

if [ -d /usr/share/doc/python3/html ]; then
    ln -sfn /usr/share/doc/python3/html "${ICPCBO_DOC_DST}/python-docs"
fi

if [ -d /usr/share/doc/openjdk-21-doc/api ]; then
    ln -sfn /usr/share/doc/openjdk-21-doc/api "${ICPCBO_DOC_DST}/java-docs"
fi
