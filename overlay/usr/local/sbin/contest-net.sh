#!/usr/bin/env bash
# Corte total / restauracion del bloqueo de red (acciones net-open / net-lock).
#   open  -> borra la tabla nftables del concurso (internet abierto)
#   lock  -> reconstruye reglas + allowlist
#   status
set -euo pipefail

TABLE="inet contest_lockdown"
RULESET="${CONTEST_NFT_RULESET:-/etc/nftables.conf}"
APPLY="${CONTEST_ALLOWLIST_APPLY:-/usr/local/sbin/contest-allowlist-apply.sh}"

case "${1:-}" in
    open)
        nft list table ${TABLE} >/dev/null 2>&1 && nft delete table ${TABLE}
        echo "red: ABIERTA (bloqueo levantado)"
        ;;
    lock)
        nft -f "${RULESET}"
        "${APPLY}"
        echo "red: BLOQUEADA (reglas + allowlist aplicadas)"
        ;;
    status)
        nft list table ${TABLE} >/dev/null 2>&1 && echo locked || echo open
        ;;
    *)
        echo "uso: $0 {open|lock|status}" >&2; exit 2
        ;;
esac
