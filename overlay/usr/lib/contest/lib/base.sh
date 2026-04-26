#!/usr/bin/env bash

require_value() {
    local value="$1"
    local label="$2"

    [ -n "${value}" ] || {
        echo "missing ${label}" >&2
        exit 1
    }
}

normalize_contest_dir() {
    local dir="${1:-/contest}"

    case "${dir}" in
        /*) printf '%s\n' "${dir}" ;;
        *) printf '/%s\n' "${dir}" ;;
    esac
}

cmdline_param() {
    local key="${1:-}"
    local cmdline_file="${CMDLINE_FILE:-/proc/cmdline}"

    require_value "${key}" "kernel cmdline key"
    tr ' ' '\n' < "${cmdline_file}" | grep -m1 "^${key}=" | cut -d= -f2- || true
}
