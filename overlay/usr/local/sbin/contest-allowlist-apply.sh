#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${CONTEST_NETLOCKDOWN_ENV:-/etc/contestiso/netlockdown.env}"
ALLOWLIST_FILE="${CONTEST_ALLOWLIST_FILE:-/etc/contestiso/allowlist.conf}"
RESOLV_CONF="${CONTEST_RESOLV_CONF:-/etc/resolv.conf}"

ALLOWLIST_BASE="${CONTEST_ALLOWLIST_BASE:-/etc/contestiso/allowlist.base}"
RULESET_FILE="${CONTEST_NFT_RULESET:-/etc/nftables.conf}"
TABLE="inet contest_lockdown"

log() { echo "[contest-allowlist] $*" >&2; }

NET_LOCKDOWN="true"
NET_DNS_SERVERS=""
NET_NTP_SERVERS=""
# shellcheck source=/dev/null
[ -r "${ENV_FILE}" ] && . "${ENV_FILE}"

if [ "${NET_LOCKDOWN}" != "true" ]; then
    nft list table ${TABLE} >/dev/null 2>&1 && nft delete table ${TABLE}
    log "NET_LOCKDOWN != true: bloqueo de red desactivado"
    exit 0
fi

if [ -z "${NET_DNS_SERVERS}" ]; then
    NET_DNS_SERVERS="$(awk '$1 == "nameserver" && $2 !~ /^127\./ && $2 != "::1" { print $2 }' \
        "${RESOLV_CONF}" 2>/dev/null | sort -u | tr '\n' ' ')"
    [ -n "${NET_DNS_SERVERS}" ] || {
        log "NET_DNS_SERVERS vacio y no hay nameserver directo en ${RESOLV_CONF}; configure un DNS"
        exit 1
    }
    log "usando DNS anunciado por la red: ${NET_DNS_SERVERS}"
fi

command -v nft >/dev/null 2>&1 || { log "nft no instalado"; exit 1; }
nft list table ${TABLE} >/dev/null 2>&1 || nft -f "${RULESET_FILE}"

is_v4() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; }
is_v6() { [[ "$1" == *:* ]]; }
join() { local IFS=,; echo "$*"; }

A4=(); A6=(); D4=(); D6=(); N4=(); HOSTS=()

add_host() {
    local host="$1"
    case "${host}" in
        ws://*|wss://*) host="$(python3 -c 'from urllib.parse import urlsplit; import sys; print(urlsplit(sys.argv[1]).hostname or "")' "${host}")" ;;
    esac
    [ -n "${host}" ] || return 0
    if is_v4 "${host}"; then A4+=("${host}"); return; fi
    if is_v6 "${host}"; then A6+=("${host}"); return; fi
    HOSTS+=("${host}")
}

resolve_hosts() {
    local ip
    [ ${#HOSTS[@]} -gt 0 ] || return 0
    while read -r ip; do
        [ -n "${ip}" ] || continue
        if is_v6 "${ip}"; then A6+=("${ip}"); else A4+=("${ip}"); fi
    done < <(printf '%s\0' "${HOSTS[@]}" | xargs -0 -r -n1 -P16 timeout 5 getent ahosts 2>/dev/null \
        | awk '{print $1}' | sort -u)
}

for s in ${NET_DNS_SERVERS}; do
    if is_v6 "${s}"; then D6+=("${s}"); else D4+=("${s}"); fi
done

# nftables arranca con los sets vacios y policy drop. Habilita DNS antes de
# resolver los nombres de la allowlist/NTP para evitar el bloqueo circular.
{
    echo "flush set ${TABLE} dns4"
    echo "flush set ${TABLE} dns6"
    [ ${#D4[@]} -gt 0 ] && echo "add element ${TABLE} dns4 { $(join "${D4[@]}") }"
    [ ${#D6[@]} -gt 0 ] && echo "add element ${TABLE} dns6 { $(join "${D6[@]}") }"
    :
} | nft -f -

for s in ${NET_NTP_SERVERS:-${NET_DNS_SERVERS}}; do
    if is_v4 "${s}"; then
        N4+=("${s}")
    elif ! is_v6 "${s}"; then
        while read -r ip; do
            is_v4 "${ip}" && N4+=("${ip}")
        done < <(timeout 5 getent ahostsv4 "${s}" 2>/dev/null | awk '{print $1}' | sort -u)
    fi
done

for f in "${ALLOWLIST_BASE}" "${ALLOWLIST_FILE}"; do
    [ -r "${f}" ] || continue
    while read -r line || [ -n "${line}" ]; do
        line="${line%%#*}"
        for tok in ${line}; do add_host "${tok}"; done
    done < "${f}"
done
resolve_hosts

{
    echo "flush set ${TABLE} allow4"
    echo "flush set ${TABLE} allow6"
    echo "flush set ${TABLE} dns4"
    echo "flush set ${TABLE} dns6"
    echo "flush set ${TABLE} ntp4"
    echo "flush chain ${TABLE} dns_redirect"
    [ ${#A4[@]} -gt 0 ] && echo "add element ${TABLE} allow4 { $(join "${A4[@]}") }"
    [ ${#A6[@]} -gt 0 ] && echo "add element ${TABLE} allow6 { $(join "${A6[@]}") }"
    [ ${#D4[@]} -gt 0 ] && echo "add element ${TABLE} dns4 { $(join "${D4[@]}") }"
    [ ${#D6[@]} -gt 0 ] && echo "add element ${TABLE} dns6 { $(join "${D6[@]}") }"
    [ ${#N4[@]} -gt 0 ] && echo "add element ${TABLE} ntp4 { $(join "${N4[@]}") }"
    # DNS forzado: reescribe cualquier consulta al puerto 53 (que no vaya ya al
    # resolver ni a loopback) hacia el primer NET_DNS_SERVERS.
    [ ${#D4[@]} -gt 0 ] && echo "add rule ${TABLE} dns_redirect meta l4proto { tcp, udp } th dport 53 ip daddr != 127.0.0.0/8 ip daddr != @dns4 dnat ip to ${D4[0]}"
    [ ${#D6[@]} -gt 0 ] && echo "add rule ${TABLE} dns_redirect meta l4proto { tcp, udp } th dport 53 ip6 daddr != ::1 ip6 daddr != @dns6 dnat ip6 to ${D6[0]}"
    :
} | nft -f -

log "allow4=${#A4[@]} allow6=${#A6[@]} dns4=${#D4[@]} dns6=${#D6[@]} ntp4=${#N4[@]}"
