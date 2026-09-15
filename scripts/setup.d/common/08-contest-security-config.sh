#!/usr/bin/env bash

set -euo pipefail

INSTALL_ROOT="${INSTALL_ROOT:-}"
INSTALL_OWNER="${INSTALL_OWNER:-root}"
INSTALL_GROUP="${INSTALL_GROUP:-root}"

root_path() {
    printf '%s%s\n' "${INSTALL_ROOT}" "$1"
}

contest_config_dir="$(root_path /etc/contestiso)"
install -d -o "${INSTALL_OWNER}" -g "${INSTALL_GROUP}" -m 0755 \
    "${contest_config_dir}"
install -d -o "${INSTALL_OWNER}" -g "${INSTALL_GROUP}" -m 0700 \
    "${contest_config_dir}/secrets"

install_optional_file() {
    local source_path="$1"
    local destination_path="$2"
    local mode="$3"

    [[ -f "${source_path}" ]] || return 0
    install -o "${INSTALL_OWNER}" -g "${INSTALL_GROUP}" -m "${mode}" \
        "${source_path}" "$(root_path "${destination_path}")"
}

install -d -o "${INSTALL_OWNER}" -g "${INSTALL_GROUP}" -m 0755 \
    "$(root_path "$(dirname "${UPDATE_SIGNATURE_PUBKEY}")")"
install_optional_file "${UPDATE_SIGNATURE_PUBKEY_SOURCE}" "${UPDATE_SIGNATURE_PUBKEY}" 0644

write_public_config() {
    local destination="$1"
    shift
    local temporary

    temporary="$(mktemp "${contest_config_dir}/.config.XXXXXX")"
    trap 'rm -f "${temporary}"' RETURN
    printf '%s\n' "$@" > "${temporary}"
    chown "${INSTALL_OWNER}:${INSTALL_GROUP}" "${temporary}"
    chmod 0644 "${temporary}"
    mv -f "${temporary}" "${destination}"
    trap - RETURN
}

write_public_config "${contest_config_dir}/security.env" \
    "UPDATE_SIGNATURE_PUBKEY=${UPDATE_SIGNATURE_PUBKEY@Q}" \
    "TEAM_ID_REQUIRED=${TEAM_ID_REQUIRED@Q}"
