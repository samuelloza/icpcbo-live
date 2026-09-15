#!/usr/bin/env bash
# ISO genérica con reasignación de región por login (modelo "lobby", ver
# control-server/groups.json.example): hook 28-region-identity.sh y su
# cableado en build.sh. REGION_ID normalmente queda vacío; contest-control.sh
# lo corrige solo cuando el equipo hace login (maybe_reenroll).
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${PROJECT_DIR}/scripts/setup.d/common/28-region-identity.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
has()  { grep -Eq -- "$2" "$1" || fail "$1 debe contener /$2/"; }

bash -n "${HOOK}" || fail "syntax error en ${HOOK}"

# -- cableado -----------------------------------------------------------
has "${PROJECT_DIR}/scripts/build.sh" 'iso_name="\$\{REGION_ID:\+\$\{REGION_ID\}-\}20260901222621"'
has "${PROJECT_DIR}/scripts/build.sh" 'REGION_ID="\$\{REGION_ID:-\}"'
has "${PROJECT_DIR}/scripts/build.sh" 'REGION_NAME="\$\{REGION_NAME:-\}"'
has "${PROJECT_DIR}/config/iso.conf"  '^REGION_ID='
has "${PROJECT_DIR}/config/iso.conf"  'GROUP_ID="\$\{GROUP_ID:-\$\{REGION_ID:-\}\}"'

# -- hook con región --------------------------------------------------
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/etc"
printf 'ICPC Bolivia Debian 13\n' > "${tmp}/etc/issue"
printf 'ID=icpc-bolivia-debian\nNAME="ICPC Bolivia Debian"\n' > "${tmp}/etc/os-release"

REGION_ROOT="${tmp}" REGION_OWNER="$(id -un)" REGION_GROUP="$(id -gn)" \
    REGION_ID="sucre" REGION_NAME="Sucre" bash "${HOOK}" >/dev/null

grep -qx 'REGION_ID=sucre' "${tmp}/etc/contestiso/region.env" || fail "region.env sin REGION_ID"
grep -qx 'REGION_NAME=Sucre' "${tmp}/etc/contestiso/region.env" || fail "region.env sin REGION_NAME"
[ "$(cat "${tmp}/etc/contest-region")" = "sucre" ] || fail "/etc/contest-region incorrecto"
grep -qx 'Region: Sucre' "${tmp}/etc/issue" || fail "/etc/issue sin la region"
grep -qx 'VARIANT_ID=sucre' "${tmp}/etc/os-release" || fail "os-release sin VARIANT_ID"
[ "$(grep -c '^Region: ' "${tmp}/etc/issue")" = "1" ] || fail "region duplicada en /etc/issue"
# idempotente
REGION_ROOT="${tmp}" REGION_OWNER="$(id -un)" REGION_GROUP="$(id -gn)" \
    REGION_ID="sucre" REGION_NAME="Sucre" bash "${HOOK}" >/dev/null
[ "$(grep -c '^Region: ' "${tmp}/etc/issue")" = "1" ] || fail "hook no es idempotente en /etc/issue"

# -- hook sin región -----------------------------------------------
tmp2="$(mktemp -d)"; mkdir -p "${tmp2}/etc"
REGION_ROOT="${tmp2}" REGION_OWNER="$(id -un)" REGION_GROUP="$(id -gn)" bash "${HOOK}" >/dev/null
grep -qE "^REGION_ID=(''|)\$" "${tmp2}/etc/contestiso/region.env" || fail "region.env vacío mal escrito"
[ ! -e "${tmp2}/etc/contest-region" ] || fail "sin REGION_ID no debe crear /etc/contest-region"
rm -rf "${tmp2}"

echo "PASS: region identity"
