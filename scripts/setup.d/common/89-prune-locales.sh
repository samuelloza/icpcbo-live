#!/usr/bin/env bash

set -euo pipefail

prune_language_dirs() {
    local root="$1"

    [[ -d "${root}" ]] || return 0

    find "${root}" -mindepth 1 -maxdepth 1 -type d \
        ! -name 'en' \
        ! -name 'en_*' \
        ! -name 'en-*' \
        ! -name 'es' \
        ! -name 'es_*' \
        ! -name 'es-*' \
        -exec rm -rf {} +
}

prune_man_dirs() {
    local root="$1"

    [[ -d "${root}" ]] || return 0

    find "${root}" -mindepth 1 -maxdepth 1 -type d \
        ! -name 'man*' \
        ! -name 'en' \
        ! -name 'en_*' \
        ! -name 'en-*' \
        ! -name 'es' \
        ! -name 'es_*' \
        ! -name 'es-*' \
        -exec rm -rf {} +
}

prune_language_dirs /usr/share/locale
prune_language_dirs /usr/share/help
prune_man_dirs /usr/share/man

