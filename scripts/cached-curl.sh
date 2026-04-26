#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: cached-curl.sh <url> <output-file>" >&2
    exit 1
fi

url="$1"
output="$2"
cache_dir="${DOWNLOAD_CACHE_DIR:-/work/download-cache}"
connections="${DOWNLOAD_CONNECTIONS:-8}"

url_hash="$(printf '%s' "${url}" | sha256sum | cut -c1-16)"
url_base="$(basename "${url%%\?*}" | tr -cs 'a-zA-Z0-9._-' '_' | cut -c1-80)"
cache_file="${cache_dir}/${url_hash}-${url_base}"

download_file() {
    local src="$1"
    local dst="$2"

    if command -v axel >/dev/null 2>&1; then
        axel -n "${connections}" -q -o "${dst}" "${src}"
        return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -q -O "${dst}" "${src}"
        return 0
    fi

    curl -fsSL "${src}" -o "${dst}"
}

if [ -d "${cache_dir}" ] && [ -w "${cache_dir}" ]; then
    if [ -f "${cache_file}" ]; then
        echo "I: [download cache] hit  : ${url}" >&2
        cp "${cache_file}" "${output}"
        exit 0
    fi

    echo "I: [download cache] miss : ${url}" >&2
    tmp_file="${cache_file}.tmp"
    rm -f "${tmp_file}"
    download_file "${url}" "${tmp_file}"
    mv "${tmp_file}" "${cache_file}"
    cp "${cache_file}" "${output}"
    exit 0
fi

echo "W: [download cache] not available at '${cache_dir}', downloading directly" >&2
download_file "${url}" "${output}"
