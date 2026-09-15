#!/usr/bin/env bash
# Verifica el resolver DNS del concurso: config valida y cableado en compose.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="${PROJECT_DIR}/control-server/dns/dnsmasq.conf"
DOCKERFILE="${PROJECT_DIR}/control-server/dns/Dockerfile"
COMPOSE="${PROJECT_DIR}/control-server/docker-compose.yml"

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -r "${CONF}" ] || fail "falta ${CONF}"
[ -r "${DOCKERFILE}" ] || fail "falta ${DOCKERFILE}"

for k in '^no-resolv' '^cache-size=' '^server='; do
    grep -Eq -- "${k}" "${CONF}" || fail "${CONF} sin ${k}"
done
grep -q 'dns/Dockerfile' "${COMPOSE}" || fail "compose no referencia el servicio dns"

if command -v dnsmasq >/dev/null 2>&1; then
    dnsmasq --test --conf-file="${CONF}" || fail "dnsmasq rechaza ${CONF}"
fi

echo "PASS: dns"
