#!/usr/bin/env bash

set -euo pipefail

ZEN_TITLE="ICPC Bolivia"
ZEN_WIDTH="--width=420"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/icpcbo"
STATE_FILE="${STATE_DIR}/user-id.txt"
DISPLAY_FILE="${STATE_DIR}/display-name.txt"
RAW_RESPONSE_FILE="${STATE_DIR}/auth-response.json"
WALLPAPER_FILE="${STATE_DIR}/login-wallpaper.svg"
AUTH_ENV_FILE="/etc/contestiso/auth.env"

AUTH_SERVICE_URL="${AUTH_SERVICE_URL:-}"
AUTH_SERVICE_TIMEOUT="${AUTH_SERVICE_TIMEOUT:-5}"

if [ -f "${AUTH_ENV_FILE}" ]; then
    # shellcheck source=/dev/null
    source "${AUTH_ENV_FILE}"
fi

require_commands() {
    local cmd

    for cmd in zenity curl python3 gsettings; do
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

    python3 - "$username" "$password" <<'PY'
import json
import os
import socket
import sys

payload = {
    "username": sys.argv[1],
    "password": sys.argv[2],
    "hostname": socket.gethostname(),
    "machineId": os.environ.get("XDG_SESSION_ID", ""),
}

print(json.dumps(payload, ensure_ascii=False))
PY
}

parse_response_env() {
    local response_file="$1"
    local http_code="$2"
    local username="$3"

    python3 - "$response_file" "$http_code" "$username" <<'PY'
import json
import shlex
import sys

response_file, http_code, username = sys.argv[1], int(sys.argv[2]), sys.argv[3]
raw = ""

try:
    with open(response_file, encoding="utf-8") as fh:
        raw = fh.read()
except FileNotFoundError:
    pass

ok = False
message = ""
user_id = username
display_name = username

if 200 <= http_code < 300:
    try:
        data = json.loads(raw or "{}")
    except json.JSONDecodeError:
        message = "El servicio respondió con un formato JSON inválido."
    else:
        ok_value = data.get("ok", data.get("valid"))
        if ok_value is None:
            ok_value = str(data.get("status", "")).lower() in {
                "ok",
                "success",
                "valid",
            }

        ok = bool(ok_value)
        message = str(data.get("message") or data.get("detail") or "")
        user_id = str(
            data.get("userId")
            or data.get("user_id")
            or data.get("id")
            or username
        )
        display_name = str(
            data.get("displayName")
            or data.get("display_name")
            or data.get("name")
            or username
        )
else:
    message = f"El servicio respondió con HTTP {http_code}."

if not ok and not message:
    message = "Las credenciales no fueron aceptadas."

print(f"AUTH_OK={shlex.quote('1' if ok else '0')}")
print(f"AUTH_MESSAGE={shlex.quote(message)}")
print(f"AUTH_USER_ID={shlex.quote(user_id)}")
print(f"AUTH_DISPLAY_NAME={shlex.quote(display_name)}")
PY
}

write_wallpaper() {
    local display_name="$1"
    local user_id="$2"

    python3 - "$display_name" "$user_id" "$WALLPAPER_FILE" <<'PY'
from html import escape
from pathlib import Path
import sys

name = sys.argv[1].strip() or "Contestant"
user_id = sys.argv[2].strip()
output = Path(sys.argv[3])
output.parent.mkdir(parents=True, exist_ok=True)

font_size = 100
if len(name) > 18:
    font_size = 80
if len(name) > 28:
    font_size = 64

subtitle = f"ID: {user_id}" if user_id else "ICPC Bolivia"

svg = f"""<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0 1920 1080">
  <rect width="1920" height="1080" fill="#000000"/>
  <text x="960" y="460" fill="#f4f0dd" font-family="Share, Fira Sans, sans-serif"
        font-size="36" text-anchor="middle" letter-spacing="8">ICPC BOLIVIA</text>
  <text x="960" y="590" fill="#ffffff" font-family="Fira Sans, sans-serif"
        font-size="{font_size}" font-weight="700" text-anchor="middle">{escape(name)}</text>
  <text x="960" y="670" fill="#8f9aa3" font-family="Fira Sans, sans-serif"
        font-size="30" text-anchor="middle">{escape(subtitle)}</text>
</svg>
"""

output.write_text(svg, encoding="utf-8")
PY
}

apply_wallpaper() {
    gsettings set org.gnome.desktop.background picture-uri "file://${WALLPAPER_FILE}"
    gsettings set org.gnome.desktop.background picture-uri-dark "file://${WALLPAPER_FILE}"
    gsettings set org.gnome.desktop.background picture-options "scaled"
    gsettings set org.gnome.desktop.background primary-color "#000000"
    gsettings set org.gnome.desktop.background secondary-color "#000000"
}

persist_login_state() {
    local user_id="$1"
    local display_name="$2"
    local response_file="$3"

    mkdir -p "${STATE_DIR}"
    printf '%s\n' "${user_id}" > "${STATE_FILE}"
    printf '%s\n' "${display_name}" > "${DISPLAY_FILE}"
    cp "${response_file}" "${RAW_RESPONSE_FILE}"
}

authenticate() {
    local username="$1"
    local password="$2"
    local payload response_file env_file http_code curl_rc

    response_file="$(mktemp)"
    env_file="$(mktemp)"
    curl_rc=0

    payload="$(build_payload "${username}" "${password}")"
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

    parse_response_env "${response_file}" "${http_code}" "${username}" > "${env_file}"
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
    persist_login_state "${AUTH_USER_ID}" "${AUTH_DISPLAY_NAME}" "${response_file}"
    if command -v logger >/dev/null 2>&1; then
        logger -p local0.info "ICPCBO-LOGIN: authenticated user ${AUTH_USER_ID}"
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
