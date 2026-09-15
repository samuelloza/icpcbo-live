#!/usr/bin/env bash
# Verifica el bloqueo de red: ruleset nftables, resolucion de la allowlist en
# sets, y que el build (packages/config/hook) lo active.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NFT_RULESET="${PROJECT_DIR}/overlay/etc/nftables.conf"
APPLY="${PROJECT_DIR}/overlay/usr/local/sbin/contest-allowlist-apply.sh"
HOOK="${PROJECT_DIR}/scripts/setup.d/common/25-network-lockdown.sh"
SERVICE="${PROJECT_DIR}/overlay/etc/systemd/system/contest-allowlist.service"
TIMER="${PROJECT_DIR}/overlay/etc/systemd/system/contest-allowlist.timer"

fail() { echo "FAIL: $*" >&2; exit 1; }
has()  { grep -Eq -- "$2" "$1" || fail "$1 debe contener /$2/"; }

# -- syntax ---------------------------------------------------------------
bash -n "${APPLY}" || fail "syntax error en ${APPLY}"
bash -n "${HOOK}"  || fail "syntax error en ${HOOK}"

# -- ruleset ------------------------------------------------------------
has "${NFT_RULESET}" 'hook output priority 0; *policy drop'
has "${NFT_RULESET}" 'hook forward priority 0; *policy drop'
has "${NFT_RULESET}" 'chain dns_redirect'
has "${NFT_RULESET}" 'type nat hook output priority -100'
has "${NFT_RULESET}" 'set allow4'
has "${NFT_RULESET}" 'ip +daddr @allow4 accept'
has "${NFT_RULESET}" 'ip +daddr @dns4 (udp|tcp) dport 53 accept'
if command -v nft >/dev/null 2>&1; then
    nft -c -f "${NFT_RULESET}" || fail "nft -c rechaza ${NFT_RULESET}"
fi

# -- build wiring -----------------------------------------------------
has "${PROJECT_DIR}/scripts/setup.d/gnome/packages.list" '^nftables$'
has "${PROJECT_DIR}/scripts/setup.d/xfce4/packages.list" '^nftables$'
has "${PROJECT_DIR}/config/iso.conf" '^NET_LOCKDOWN='
has "${HOOK}" 'systemctl enable nftables.service contest-allowlist.service contest-allowlist.timer'
has "${SERVICE}" 'ExecStart=/usr/local/sbin/contest-allowlist-apply.sh'
has "${TIMER}" 'WantedBy=timers.target'

# -- apply script: resuelve la allowlist en un batch de nft --------------
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
bin="${tmp}/bin"; mkdir -p "${bin}"
batch="${tmp}/nft-batch.txt"; : > "${batch}"

cat > "${bin}/nft" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "list table inet contest_lockdown") exit 0 ;;          # tabla ya existe
  "-f -") cat >> "${batch}" ; exit 0 ;;
  "delete table inet contest_lockdown") echo DELETE_TABLE >> "${batch}" ; exit 0 ;;
  *) exit 0 ;;
esac
EOF
cat > "${bin}/getent" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "ahosts" ] || exit 2
case "${2:-}" in
  allowed.example) printf '203.0.113.7 STREAM allowed.example\n2001:db8::7 STREAM\n' ;;
  *) exit 2 ;;
esac
EOF
chmod +x "${bin}/nft" "${bin}/getent"

cat > "${tmp}/netlockdown.env" <<'EOF'
NET_LOCKDOWN=true
NET_DNS_SERVERS="10.0.0.1 10.0.0.2"
EOF
cat > "${tmp}/allowlist.conf" <<'EOF'
# comentario
allowed.example
198.51.100.4
2001:db8::99   # inline
EOF

PATH="${bin}:${PATH}" \
CONTEST_NETLOCKDOWN_ENV="${tmp}/netlockdown.env" \
CONTEST_ALLOWLIST_FILE="${tmp}/allowlist.conf" \
    bash "${APPLY}" || fail "apply script fallo"

grep -Eq 'add element inet contest_lockdown allow4 \{[^}]*203\.0\.113\.7' "${batch}" \
    || fail "hostname no resuelto a allow4: $(cat "${batch}")"
grep -Eq 'add element inet contest_lockdown allow4 \{[^}]*198\.51\.100\.4' "${batch}" \
    || fail "IPv4 literal no agregada a allow4"
grep -Eq 'add element inet contest_lockdown allow6 \{[^}]*2001:db8::7'  "${batch}" \
    || fail "IPv6 resuelta no agregada a allow6"
grep -Eq 'add element inet contest_lockdown allow6 \{[^}]*2001:db8::99' "${batch}" \
    || fail "IPv6 literal no agregada a allow6"
grep -Eq 'add element inet contest_lockdown dns4 \{ *10\.0\.0\.1,10\.0\.0\.2 *\}' "${batch}" \
    || fail "dns4 no cargado desde NET_DNS_SERVERS"
grep -Eq 'add element inet contest_lockdown ntp4 \{ *10\.0\.0\.1,10\.0\.0\.2 *\}' "${batch}" \
    || fail "ntp4 no cayo por defecto a NET_DNS_SERVERS"
grep -Eq 'add rule inet contest_lockdown dns_redirect .*dport 53 .*dnat ip to 10\.0\.0\.1' "${batch}" \
    || fail "DNS forzado: falta la regla dnat al primer NET_DNS_SERVERS: $(cat "${batch}")"

# NET_LOCKDOWN=false debe abrir la red (borra la tabla)
echo 'NET_LOCKDOWN=false' > "${tmp}/netlockdown.env"
: > "${batch}"
PATH="${bin}:${PATH}" CONTEST_NETLOCKDOWN_ENV="${tmp}/netlockdown.env" \
    bash "${APPLY}" || fail "apply script fallo con lockdown desactivado"
grep -q DELETE_TABLE "${batch}" || fail "con NET_LOCKDOWN=false debe borrar la tabla"

echo "PASS: network lockdown"
