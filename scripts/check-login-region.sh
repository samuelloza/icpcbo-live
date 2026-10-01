#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/iso.conf
source "${PROJECT_DIR}/config/iso.conf"

username="${1:-}"
[ -n "${username}" ] || read -rp "Usuario: " username
read -rsp "Password: " password
echo

response="$(mktemp)"
trap 'rm -f "${response}"' EXIT
payload="$(python3 "${PROJECT_DIR}/assets/contestants/bin/contestants-login-build-payload.py" \
    "${username}" "${password}")"

code="$(curl --silent --show-error --output "${response}" --write-out '%{http_code}' \
    --header 'Content-Type: application/json' --data "${payload}" "${AUTH_SERVICE_URL}")"

python3 - "${response}" "${code}" <<'PY'
import json
import sys

path, code = sys.argv[1], int(sys.argv[2])
try:
    data = json.load(open(path, encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    raise SystemExit(f"ERROR: respuesta inválida (HTTP {code}): {exc}")

region = data.get("region") if isinstance(data.get("region"), dict) else {}
print(f"HTTP={code}")
print(f"OK={data.get('ok', False)}")
print(f"AUTHENTICATED={data.get('authenticated', '')}")
print(f"HAS_ACTIVE_EXAM={data.get('hasActiveExam', '')}")
print(f"USER_ID={data.get('userId', '')}")
print(f"REGION_ID={region.get('id', '')}")
print(f"REGION_NAME={region.get('name', '')}")
print(f"ENROLL_TOKEN={'OK' if region.get('enrollToken') else 'FALTANTE'}")
print(f"MESSAGE={data.get('message', '')}")

if not 200 <= code < 300 or not data.get("ok"):
    raise SystemExit(f"ERROR: {data.get('message', 'login rechazado')}")
if not region.get("id"):
    if data.get("hasActiveExam") is False:
        raise SystemExit("ERROR: el usuario no tiene un examen activo asignado")
    raise SystemExit("ERROR: el login no devolvió el grupo del examen")
if not region.get("enrollToken"):
    raise SystemExit("ERROR: la region no existe o no tiene enroll_token en groups.json")
PY
