#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: cached-curl.sh <url> <output-file>" >&2
    exit 1
fi

url="$1"
output="$2"
cache_dir="${DOWNLOAD_CACHE_DIR}"
connections="${DOWNLOAD_CONNECTIONS}"

url_hash="$(printf '%s' "${url}" | sha256sum | cut -c1-16)"
url_base="$(basename "${url%%\?*}" | tr -cs 'a-zA-Z0-9._-' '_' | cut -c1-80)"
cache_file="${cache_dir}/${url_hash}-${url_base}"
partial_file="${cache_file}.tmp"

migrate_old_partial_file() {
    local cache_name
    local old_partial_file

    if [ -f "${partial_file}" ]; then
        return 0
    fi

    cache_name="$(basename "${cache_file}")"
    old_partial_file="$(
        find "${cache_dir}" -maxdepth 1 -type f \
            -name "${cache_name}.*.tmp" 2>/dev/null | head -n 1 || true
    )"

    if [ -n "${old_partial_file}" ]; then
        echo "I: [download cache] resume partial: ${url}" >&2
        mv "${old_partial_file}" "${partial_file}"

        if [ -f "${old_partial_file}.st" ]; then
            mv "${old_partial_file}.st" "${partial_file}.st"
        fi
    fi
}

download_file() {
    local src="$1"
    local dst="$2"

    if command -v axel >/dev/null 2>&1; then
        axel -n "${connections}" -q -o "${dst}" "${src}"
        return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -q -c -O "${dst}" "${src}"
        return 0
    fi

    if [ -f "${dst}" ]; then
        curl -fSL -C - "${src}" -o "${dst}"
        return 0
    fi

    curl -fSL "${src}" -o "${dst}"
}

copy_from_cache() {
    echo "I: [download cache] hit  : ${url}" >&2
    cp "${cache_file}" "${output}"
}

save_to_cache() {
    migrate_old_partial_file

    if [ -f "${partial_file}" ]; then
        echo "I: [download cache] resume: ${url}" >&2
    else
        echo "I: [download cache] miss : ${url}" >&2
    fi

    download_file "${url}" "${partial_file}"
    mv "${partial_file}" "${cache_file}"
    rm -f "${partial_file}.st"
    cp "${cache_file}" "${output}"
}

if [ -f "${cache_file}" ]; then
    copy_from_cache
    exit 0
fi

if [ -d "${cache_dir}" ] && [ -w "${cache_dir}" ]; then
    save_to_cache
    exit 0
fi

echo "W: [download cache] not available at '${cache_dir}', downloading directly" >&2
download_file "${url}" "${output}"
