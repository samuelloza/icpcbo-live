#!/usr/bin/env bash
# Agente de metricas pulso (fork https://github.com/samuelloza/pulso).
set -euo pipefail

PULSO_RELEASE_URL="${PULSO_RELEASE_URL:-}"
BIN=/usr/local/bin/pulso

if [ -z "${PULSO_PUSHGATEWAY_URL:-}" ]; then
    echo "PULSO_PUSHGATEWAY_URL vacio: agente pulso no se activa"
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
if ! /tmp/cached-curl.sh "${PULSO_RELEASE_URL}" "${work}/pulso.tar.gz"; then
    echo "FATAL: no se pudo descargar pulso desde ${PULSO_RELEASE_URL}" >&2
    exit 1
fi
tar -xzf "${work}/pulso.tar.gz" -C "${work}"
src="$(find "${work}" -type f -name pulso | head -n1)"
[ -n "${src}" ] || { echo "FATAL: el tarball de pulso no trae un binario 'pulso'" >&2; exit 1; }
install -m 0755 "${src}" "${BIN}"

if ldd "${BIN}" 2>&1 | grep -q 'not found'; then
    ldd "${BIN}" || true
    echo "FATAL: a ${BIN} le faltan libs compartidas" >&2
    exit 1
fi

esc="${PULSO_PUSHGATEWAY_URL//\\/\\\\}"; esc="${esc//&/\\&}"; esc="${esc//|/\\|}"
sed -i "s|^url = .*|url = \"${esc}\"|" /etc/pulso/pulso.toml

[ -n "${PULSO_JOB:-}" ] && sed -i "s|^job = .*|job = \"${PULSO_JOB}\"|" /etc/pulso/pulso.toml

systemctl enable pulso.service
