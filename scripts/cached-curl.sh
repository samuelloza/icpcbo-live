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

# Descarga con timeouts y reintentos. Cada herramienta se prueba con un tope de
# tiempo de pared (timeout(1)); si falla o se cuelga, se pasa a la siguiente.
DOWNLOAD_CONNECT_TIMEOUT="${DOWNLOAD_CONNECT_TIMEOUT:-30}"
DOWNLOAD_WALL_TIMEOUT="${DOWNLOAD_WALL_TIMEOUT:-1800}"

_with_timeout() {
    if command -v timeout >/dev/null 2>&1; then
        timeout --kill-after=15 "${DOWNLOAD_WALL_TIMEOUT}" "$@"
    else
        "$@"
    fi
}

_curl_download() {
    local src="$1" dst="$2"
    _with_timeout curl -fSL --retry 3 --retry-delay 2 \
        --connect-timeout "${DOWNLOAD_CONNECT_TIMEOUT}" -C - -o "${dst}" "${src}" && return 0
    rm -f "${dst}"
    _with_timeout curl -fSL --retry 3 --retry-delay 2 \
        --connect-timeout "${DOWNLOAD_CONNECT_TIMEOUT}" -o "${dst}" "${src}"
}

download_file() {
    local src="$1"
    local dst="$2"

    case "${src}" in
        *microsoft.com*|*visualstudio.com*|*githubusercontent*|*github.com*/*releases/*|*jetbrains.com*|*download.jetbrains*)
            _curl_download "${src}" "${dst}"
            return $?
            ;;
    esac

    if command -v axel >/dev/null 2>&1; then
        if _with_timeout axel -n "${connections}" -T "${DOWNLOAD_CONNECT_TIMEOUT}" \
            -o "${dst}" "${src}"; then
            return 0
        fi
        echo "W: axel falló/expiró, cayendo a curl..." >&2
        rm -f "${dst}" "${dst}.st"
    fi

    _curl_download "${src}" "${dst}"
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
