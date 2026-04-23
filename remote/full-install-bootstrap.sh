#!/usr/bin/env bash
# Bootstrap remoto de full-install.
# Solo descarga y ejecuta `full-install.sh`.

set -euo pipefail

LOG="/var/log/contest-full-install.log"
RUNTIME_DIR="/run/contest-full-install"
BOOTSTRAP_URL="${FULL_INSTALL_URL:-}"
PAYLOAD_URL="${FULL_INSTALL_PAYLOAD_URL:-}"
REMOTE_SCRIPT="${RUNTIME_DIR}/full-install.remote.sh"

log() {
    local ts
    ts=$(date -u +%H:%M:%S)
    echo "[${ts}] [bootstrap] $*" | tee -a "${LOG}"
}

mkdir -p /var/log "${RUNTIME_DIR}"
touch "${LOG}"

echo "" | tee -a "${LOG}"
echo "╔══════════════════════════════════════════════════╗" | tee -a "${LOG}"
echo "║     ICPC Bolivia — Bootstrap instalador full    ║" | tee -a "${LOG}"
echo "╚══════════════════════════════════════════════════╝" | tee -a "${LOG}"
echo "" | tee -a "${LOG}"

if [ -z "${BOOTSTRAP_URL}" ]; then
    log "FATAL: FULL_INSTALL_URL is empty"
    exit 1
fi

command -v curl >/dev/null 2>&1 || {
    log "FATAL: curl is required"
    exit 1
}

if [ -z "${PAYLOAD_URL}" ]; then
    PAYLOAD_URL="${BOOTSTRAP_URL%/*}/full-install.sh"
fi

log "Bootstrap remoto cargado desde ${BOOTSTRAP_URL}"
log "Descargando instalador real desde ${PAYLOAD_URL}"

curl --fail --show-error --location \
    --retry 12 --retry-delay 5 --retry-connrefused \
    --output "${REMOTE_SCRIPT}" "${PAYLOAD_URL}" || {
    log "FATAL: No se pudo descargar el instalador remoto"
    exit 1
}

if [ ! -s "${REMOTE_SCRIPT}" ]; then
    log "FATAL: El instalador remoto descargado está vacío"
    exit 1
fi

chmod +x "${REMOTE_SCRIPT}"

if [ -n "${FULL_INSTALL_SHA256:-}" ]; then
    command -v sha256sum >/dev/null 2>&1 || {
        log "FATAL: sha256sum is required"
        exit 1
    }

    if [ "$(sha256sum "${REMOTE_SCRIPT}" | awk '{print $1}')" != "${FULL_INSTALL_SHA256}" ]; then
        log "FATAL: SHA256 inválido para instalador remoto"
        exit 1
    fi

    log "Instalador remoto verificado correctamente"
else
    log "SHA256 no configurado; omitiendo validación del instalador remoto"
fi

log "Ejecutando instalador remoto ${REMOTE_SCRIPT}"
exec /usr/bin/env bash "${REMOTE_SCRIPT}" "$@"
