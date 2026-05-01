#!/usr/bin/env bash

set -euo pipefail

ZEN_TITLE="ICPC Bolivia"
ZEN_WIDTH="--width=420"
STATE_DIR="/home/icpc/.local/state/icpcbo"
STATE_FILE="/home/icpc/.local/state/icpcbo/user-id.txt"
USERNAME_FILE="/home/icpc/.local/state/icpcbo/username.txt"
DISPLAY_FILE="/home/icpc/.local/state/icpcbo/display-name.txt"
RAW_RESPONSE_FILE="/home/icpc/.local/state/icpcbo/auth-response.json"
WALLPAPER_FILE="/home/icpc/.local/state/icpcbo/login-wallpaper.svg"
AUTH_ENV_FILE="/etc/contestiso/auth.env"
BUILD_PAYLOAD_PY="/opt/icpc/bin/contestants-login-build-payload.py"
PARSE_RESPONSE_PY="/opt/icpc/bin/contestants-login-parse-response.py"
WRITE_WALLPAPER_PY="/opt/icpc/bin/contestants-login-write-wallpaper.py"

AUTH_SERVICE_URL="${AUTH_SERVICE_URL:-}"
AUTH_SERVICE_TIMEOUT="${AUTH_SERVICE_TIMEOUT:-5}"

if [ -f "${AUTH_ENV_FILE}" ]; then
    # shellcheck source=/dev/null
    source "${AUTH_ENV_FILE}"
fi

require_commands() {
    local cmd

    if ! command -v zenity >/dev/null 2>&1; then
        printf 'Falta la dependencia requerida: zenity\n' >&2
        exit 4
    fi

    for cmd in curl python3 gsettings; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            zenity --error "${ZEN_WIDTH}" --title "${ZEN_TITLE}" \
                --text="Falta la dependencia requerida: ${cmd}"
            exit 4
        fi
    done
}

build_payload() {
    local username="$1"
    local password="$2"

    python3 "${BUILD_PAYLOAD_PY}" "${username}" "${password}"
}

parse_response_env() {
    local response_file="$1"
    local http_code="$2"
    local username="$3"

    python3 "${PARSE_RESPONSE_PY}" "${response_file}" "${http_code}" "${username}"
}

write_wallpaper() {
    local display_name="$1"
    local user_id="$2"

    python3 "${WRITE_WALLPAPER_PY}" "${display_name}" "${user_id}" "${WALLPAPER_FILE}"
}

apply_wallpaper() {
    gsettings set org.gnome.desktop.background picture-uri "file://${WALLPAPER_FILE}"
    gsettings set org.gnome.desktop.background picture-uri-dark "file://${WALLPAPER_FILE}"
    gsettings set org.gnome.desktop.background picture-options "scaled"
    gsettings set org.gnome.desktop.background primary-color "#000000"
    gsettings set org.gnome.desktop.background secondary-color "#000000"
}

persist_login_state() {
    local username="$1"
    local user_id="$2"
    local display_name="$3"
    local response_file="$4"

    mkdir -p "${STATE_DIR}"
    printf '%s\n' "${username}" > "${USERNAME_FILE}"
    printf '%s\n' "${user_id}" > "${STATE_FILE}"
    printf '%s\n' "${display_name}" > "${DISPLAY_FILE}"
    cp "${response_file}" "${RAW_RESPONSE_FILE}"
}

authenticate() {
    local user_id="$1"
    local password="$2"
    local payload response_file env_file http_code curl_rc

    response_file="$(mktemp)"
    env_file="$(mktemp)"
    curl_rc=0

    payload="$(build_payload "${user_id}" "${password}")"
    http_code="$(curl \
        --silent --show-error \
        --max-time "${AUTH_SERVICE_TIMEOUT}" \
        --output "${response_file}" \
        --write-out '%{http_code}' \
        --header 'Content-Type: application/json' \
        --data "${payload}" \
        "${AUTH_SERVICE_URL}")" || curl_rc=$?

    if [ "${curl_rc}" -ne 0 ]; then
        rm -f "${response_file}" "${env_file}"
        zenity --error "${ZEN_WIDTH}" --title "${ZEN_TITLE}" \
            --text="No se pudo contactar el servicio de autenticación."
        return 2
    fi

    parse_response_env "${response_file}" "${http_code}" "${user_id}" > "${env_file}"
    # shellcheck source=/dev/null
    source "${env_file}"

    if [ "${AUTH_OK}" != "1" ]; then
        rm -f "${response_file}" "${env_file}"
        zenity --error "${ZEN_WIDTH}" --title "${ZEN_TITLE}" \
            --text="${AUTH_MESSAGE}"
        return 3
    fi

    write_wallpaper "${AUTH_DISPLAY_NAME}" "${AUTH_USER_ID}"
    apply_wallpaper
    persist_login_state "${user_id}" "${AUTH_USER_ID}" "${AUTH_DISPLAY_NAME}" "${response_file}"
    if command -v logger >/dev/null 2>&1; then
        logger -p local0.info "ICPCBO-LOGIN: authenticated username ${user_id} with id ${AUTH_USER_ID}"
    fi

    rm -f "${response_file}" "${env_file}"

    zenity --info "${ZEN_WIDTH}" --title "${ZEN_TITLE}" \
        --text="Inicio de sesión correcto para ${AUTH_DISPLAY_NAME}."
    return 0
}

main() {
    local credentials username password

    require_commands

    if [ -z "${AUTH_SERVICE_URL}" ]; then
        zenity --error "${ZEN_WIDTH}" --title "${ZEN_TITLE}" \
            --text="AUTH_SERVICE_URL no está configurado en /etc/contestiso/auth.env."
        exit 2
    fi

    while true; do
        credentials="$(
            zenity --forms "${ZEN_WIDTH}" --title "${ZEN_TITLE}" \
                --text="Ingrese sus credenciales del concurso." \
                --separator="|" \
                --add-entry="Usuario" \
                --add-password="Contraseña"
        )" || exit 1

        username="${credentials%%|*}"
        password="${credentials#*|}"

        if [ -z "${username}" ] || [ -z "${password}" ]; then
            zenity --error "${ZEN_WIDTH}" --title "${ZEN_TITLE}" \
                --text="Usuario y contraseña son obligatorios."
            continue
        fi

        authenticate "${username}" "${password}" && exit 0
    done
}

main "$@"
