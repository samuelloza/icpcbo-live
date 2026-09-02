#!/usr/bin/env bash

set -euo pipefail

ZEN_TITLE="ICPC Bolivia"
ZEN_WIDTH="--width=420"

STATE_FILE="/home/icpc/.local/state/icpcbo/user-id.txt"
USERNAME_FILE="/home/icpc/.local/state/icpcbo/username.txt"
DISPLAY_FILE="/home/icpc/.local/state/icpcbo/display-name.txt"
TEAM_ID_FILE="/home/icpc/.local/state/icpcbo/team-id.txt"
TEAM_NAME_FILE="/home/icpc/.local/state/icpcbo/team-name.txt"
RAW_RESPONSE_FILE="/home/icpc/.local/state/icpcbo/auth-response.json"
WALLPAPER_FILE="/home/icpc/.local/state/icpcbo/login-wallpaper.svg"

AUTH_ENV_FILE="/etc/contestiso/auth.env"
BUILD_PAYLOAD_PY="/opt/icpc/bin/contestants-login-build-payload.py"
PARSE_RESPONSE_PY="/opt/icpc/bin/contestants-login-parse-response.py"
WRITE_WALLPAPER_PY="/opt/icpc/bin/contestants-login-write-wallpaper.py"

if [ -n "${CONTEST_LOGIN_STATE_DIR:-}" ]; then
    STATE_FILE="${CONTEST_LOGIN_STATE_DIR}/user-id.txt"
    USERNAME_FILE="${CONTEST_LOGIN_STATE_DIR}/username.txt"
    DISPLAY_FILE="${CONTEST_LOGIN_STATE_DIR}/display-name.txt"
    TEAM_ID_FILE="${CONTEST_LOGIN_STATE_DIR}/team-id.txt"
    TEAM_NAME_FILE="${CONTEST_LOGIN_STATE_DIR}/team-name.txt"
    RAW_RESPONSE_FILE="${CONTEST_LOGIN_STATE_DIR}/auth-response.json"
    WALLPAPER_FILE="${CONTEST_LOGIN_STATE_DIR}/login-wallpaper.svg"
fi

STATE_DIR="$(dirname "${STATE_FILE}")"

AUTH_SERVICE_URL="${AUTH_SERVICE_URL:-}"
AUTH_SERVICE_TIMEOUT="${AUTH_SERVICE_TIMEOUT:-5}"
TEAM_ID_REQUIRED="${TEAM_ID_REQUIRED:-true}"

if [ -f "${AUTH_ENV_FILE}" ]; then
    # shellcheck source=/dev/null
    source "${AUTH_ENV_FILE}"
fi

write_wallpaper() {
    local team_name="$1"
    local team_id="$2"

    python3 "${WRITE_WALLPAPER_PY}" "${team_name}" "${team_id}" "${WALLPAPER_FILE}"
}

apply_wallpaper() {
    local property

    while IFS= read -r property; do
        [ -n "${property}" ] || continue
        xfconf-query -c xfce4-desktop -p "${property}" -s "${WALLPAPER_FILE}" || true
    done < <(xfconf-query -c xfce4-desktop -l | grep "workspace0/last-image" || true)
}

persist_login_state() {
    local username="$1"
    local user_id="$2"
    local display_name="$3"
    local team_id="$4"
    local team_name="$5"
    local response_file="$6"
    local response_tmp

    mkdir -p "${STATE_DIR}"
    chmod 0700 "${STATE_DIR}"
    atomic_write "${username}" "${USERNAME_FILE}"
    atomic_write "${user_id}" "${STATE_FILE}"
    atomic_write "${display_name}" "${DISPLAY_FILE}"
    atomic_write "${team_id}" "${TEAM_ID_FILE}"
    atomic_write "${team_name}" "${TEAM_NAME_FILE}"
    response_tmp="$(mktemp "${STATE_DIR}/.auth-response.XXXXXX")"
    cp "${response_file}" "${response_tmp}"
    chmod 0600 "${response_tmp}"
    mv -f "${response_tmp}" "${RAW_RESPONSE_FILE}"
}

atomic_write() {
    local value="$1"
    local destination="$2"
    local temporary

    temporary="$(mktemp "${STATE_DIR}/.identity.XXXXXX")"
    printf '%s\n' "${value}" > "${temporary}"
    chmod 0600 "${temporary}"
    mv -f "${temporary}" "${destination}"
}

authenticate() {
    local username="$1"
    local password="$2"
    local payload
    local response_file
    local env_file
    local http_code
    local curl_rc

    response_file="$(mktemp)"
    env_file="$(mktemp)"
    curl_rc=0

    payload="$(python3 "${BUILD_PAYLOAD_PY}" "${username}" "${password}")"
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

    python3 "${PARSE_RESPONSE_PY}" \
        "${response_file}" "${http_code}" "${username}" "${TEAM_ID_REQUIRED}" > "${env_file}"
    # shellcheck source=/dev/null
    source "${env_file}"

    if [ "${AUTH_OK}" != "1" ]; then
        rm -f "${response_file}" "${env_file}"
        zenity --error "${ZEN_WIDTH}" --title "${ZEN_TITLE}" \
            --text="${AUTH_MESSAGE}"
        return 3
    fi

    write_wallpaper "${AUTH_TEAM_NAME}" "${AUTH_TEAM_ID}"
    apply_wallpaper
    persist_login_state \
        "${username}" "${AUTH_USER_ID}" "${AUTH_DISPLAY_NAME}" \
        "${AUTH_TEAM_ID}" "${AUTH_TEAM_NAME}" "${response_file}"

    logger -p local0.info "ICPCBO-LOGIN: authenticated team_id=${AUTH_TEAM_ID}" || true

    rm -f "${response_file}" "${env_file}"
    zenity --info "${ZEN_WIDTH}" --title "${ZEN_TITLE}" \
        --text="Inicio de sesión correcto para el equipo ${AUTH_TEAM_NAME}."
    return 0
}

# Espera a que haya un entorno gráfico usable (autostart puede correr antes de
# que el display/bus estén listos: es la causa habitual de "no aparecen los
# campos").
wait_for_gui() {
    local tries=0 limit="${CONTEST_LOGIN_GUI_WAIT:-30}"
    while [ "${tries}" -lt "${limit}" ]; do
        if [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] && \
           command -v zenity >/dev/null 2>&1 && \
           zenity --version >/dev/null 2>&1; then
            return 0
        fi
        tries=$((tries + 1))
        sleep 1
    done
    return 1
}

main() {
    local credentials username password rc

    if ! wait_for_gui; then
        logger -p local0.err "ICPCBO-LOGIN: sin entorno grafico tras la espera; se reintenta al proximo arranque" || true
        exit 0
    fi

    # Config incompleta: no salir en silencio; mantener el aviso y reintentar
    # (por si auth.env llega tarde o un encargado lo corrige).
    while [ -z "${AUTH_SERVICE_URL}" ]; do
        logger -p local0.err "ICPCBO-LOGIN: AUTH_SERVICE_URL vacio en ${AUTH_ENV_FILE}" || true
        zenity --error "${ZEN_WIDTH}" --title "${ZEN_TITLE}" \
            --text="Configuración incompleta: falta AUTH_SERVICE_URL en ${AUTH_ENV_FILE}.\nAvise a un encargado. Reintentando en 10 s..."
        sleep 10
        [ -f "${AUTH_ENV_FILE}" ] && source "${AUTH_ENV_FILE}"
    done

    while true; do
        rc=0
        credentials="$(
            zenity --forms "${ZEN_WIDTH}" --title "${ZEN_TITLE}" \
                --text="Ingrese sus credenciales del concurso." \
                --separator="|" \
                --add-entry="Usuario" \
                --add-password="Contraseña"
        )" || rc=$?

        # rc=1 = el usuario cerró/canceló → se vuelve a ofrecer (login obligatorio).
        # rc>1 = zenity falló → registrar y reintentar sin abortar la sesión.
        if [ "${rc}" -gt 1 ]; then
            logger -p local0.err "ICPCBO-LOGIN: zenity --forms fallo (rc=${rc})" || true
            sleep 3
            continue
        fi
        [ "${rc}" -eq 0 ] || continue

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

if [[ "${CONTEST_LOGIN_LIBRARY_ONLY:-0}" != "1" ]]; then
    main "$@"
fi
