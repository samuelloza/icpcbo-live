#!/usr/bin/env bash

set -euo pipefail
exit
PROFILE_DIR="/tmp/contestant-vm"
CACHE_DIR="/tmp/cache"
DOC_DST="/usr/share/doc/icpcbo"
FONT_DST="${DOC_DST}/fonts"

mkdir -p "${DOC_DST}" "${FONT_DST}" "${CACHE_DIR}"

if [ -d "${PROFILE_DIR}/files/html" ]; then
    cp -a "${PROFILE_DIR}/files/html/." "${DOC_DST}/"
fi

/tmp/cached-curl.sh "https://gwfh.mranftl.com/api/fonts/fira-sans?download=zip&subsets=latin&variants=regular" "${CACHE_DIR}/fira-sans.zip" || true
/tmp/cached-curl.sh "https://gwfh.mranftl.com/api/fonts/share?download=zip&subsets=latin&variants=regular" "${CACHE_DIR}/share.zip" || true

[ -f "${CACHE_DIR}/fira-sans.zip" ] && unzip -o "${CACHE_DIR}/fira-sans.zip" -d "${FONT_DST}" >/dev/null || true
[ -f "${CACHE_DIR}/share.zip" ] && unzip -o "${CACHE_DIR}/share.zip" -d "${FONT_DST}" >/dev/null || true
