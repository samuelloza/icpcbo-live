#!/usr/bin/env bash
# contest-control.sh (single-shot): enrola, verifica firma Ed25519, despacha
# la accion, deduplica por nonce y rechaza firmas invalidas.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT="${PROJECT_DIR}/overlay/usr/local/sbin/contest-control.sh"
HOOK="${PROJECT_DIR}/scripts/setup.d/common/27-contest-control.sh"
SVC="${PROJECT_DIR}/overlay/etc/systemd/system/contest-control.service"

fail() { echo "FAIL: $*" >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "SKIP: openssl no disponible"; exit 0; }

bash -n "${CLIENT}" || fail "syntax error en ${CLIENT}"
bash -n "${HOOK}"   || fail "syntax error en ${HOOK}"
bash -n "${PROJECT_DIR}/overlay/usr/local/sbin/contest-alert.sh"
bash -n "${PROJECT_DIR}/overlay/usr/local/sbin/contest-net.sh"
bash -n "${PROJECT_DIR}/overlay/usr/local/sbin/contest-lock-guard.sh"
grep -q 'systemctl enable contest-control.service' "${HOOK}" || fail "el hook debe habilitar contest-control.service"
grep -q 'ExecStart=/usr/local/sbin/contest-control.sh --loop' "${SVC}" || fail "el servicio debe correr en modo --loop"
grep -q 'CONTROL_SERVICE_URL=' "${PROJECT_DIR}/scripts/build.sh" || fail "build.sh debe pasar CONTROL_SERVICE_URL"
grep -q 'LOCKSCREEN_PASSWORD' "${PROJECT_DIR}/scripts/build.sh" || fail "build.sh debe pasar LOCKSCREEN_PASSWORD"

tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
key="${tmp}/k.key"; pub="${tmp}/k.pub"
openssl genpkey -algorithm ed25519 -out "${key}" 2>/dev/null
openssl pkey -in "${key}" -pubout -out "${pub}" 2>/dev/null

mk_cmd() {  # action  -> prints "payload_b64|sig_b64"
    local action="$1" p="${tmp}/p.json"
    python3 - "${p}" "${action}" <<'PY'
import json, sys, datetime
exp = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
obj = {"action": sys.argv[2], "args": {"text": "hola"} if sys.argv[2] == "message" else {},
       "expires_at": exp, "group_id": "lab-x", "issued_at": "2026-01-01T00:00:00Z",
       "machine_id": "test-machine", "nonce": "N1", "server": "t"}
open(sys.argv[1], "wb").write(json.dumps(obj, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode() + b"\n")
PY
    printf '%s|%s' "$(openssl base64 -A -in "${p}")" "$(openssl pkeyutl -sign -rawin -inkey "${key}" -in "${p}" | openssl base64 -A)"
}

bin="${tmp}/bin"; sbin="${tmp}/sbin"; state="${tmp}/state"
mkdir -p "${bin}" "${sbin}" "${state}"
actions="${tmp}/actions.log"; : > "${actions}"

write_curl() {  # payload_b64 sig_b64
    cat > "${bin}/curl" <<EOF
#!/usr/bin/env bash
args="\$*"
case "\$args" in
  *X\ POST*/enroll*)  printf '{"bearer":"tok"}\n200' ;;
  *X\ GET*/cmd/*)      printf '{"nonce":"N1","payload_b64":"$1","signature":"$2"}\n200' ;;
  *X\ POST*/ack*)      echo "\$args" >> "${tmp}/ack.log"; printf '{"ok":true}\n200' ;;
  *X\ POST*/status*)   echo status >> "${tmp}/status.log"; printf '{"ok":true}\n200' ;;
  *X\ POST*/journal*)  printf '{"ok":true}\n200' ;;
  *X\ POST*/events*)   printf '{"ok":true}\n200' ;;
  *)                   printf '\n000' ;;
esac
EOF
    chmod +x "${bin}/curl"
}

printf '#!/bin/sh\necho test-machine\n' > "${bin}/machine-id"
printf '#!/bin/sh\nexit 0\n' > "${bin}/systemctl"
printf '#!/bin/sh\necho contest-host\n' > "${bin}/hostname"
printf '#!/bin/sh\necho none\n' > "${bin}/systemd-detect-virt"
printf '#!/bin/sh\n:\n' > "${bin}/journalctl"
for s in contest-session.sh contest-set-wallpaper.sh contest-net.sh contest-alert.sh contest-allowlist-apply.sh; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\n' "${s%.sh}" "${actions}" > "${sbin}/${s}"
done
cat > "${sbin}/contest-usb-storage.sh" <<EOF
#!/usr/bin/env bash
[ "\$1" = status ] && { echo blocked; exit 0; }
echo "usb \$*" >> "${actions}"
EOF
chmod +x "${bin}"/* "${sbin}"/*

cat > "${tmp}/control.env" <<EOF
CONTROL_SERVICE_URL=http://control.test
CONTROL_TIMEOUT=5
CONTROL_LONGPOLL_WAIT=1
ALLOW_VM=true
EOF
printf 'GROUP_ID=lab-x\nENROLL_TOKEN=tok\n' > "${tmp}/identity.env"

run() {
    PATH="${bin}:${PATH}" \
    CONTEST_CONTROL_ENV="${tmp}/control.env" CONTEST_CONTROL_IDENTITY="${tmp}/identity.env" \
    CONTEST_CONTROL_STATE="${state}" CONTEST_CONTROL_PUBKEY="${pub}" \
    CONTEST_MACHINE_ID_CMD="${bin}/machine-id" CONTEST_CONTROL_SBIN="${sbin}" \
    CONTEST_BINDING_FILE="${tmp}/binding.env" \
        bash "${CLIENT}"
}

# message
IFS='|' read -r P S <<< "$(mk_cmd message)"; write_curl "${P}" "${S}"
run
grep -qx 'contest-session message hola' "${actions}" || fail "no despacho message: $(cat "${actions}")"
grep -q '"status": "ok"\|"status":"ok"' "${tmp}/ack.log" || fail "no hizo ack ok"
[ -s "${tmp}/status.log" ] || fail "no mando telemetria (status)"
[ -f "${state}/applied/N1" ] || fail "no marco el nonce aplicado"

# dedupe
: > "${actions}"; : > "${tmp}/ack.log"
run
[ -s "${actions}" ] && fail "re-ejecuto un comando ya aplicado"
grep -q 'duplicate' "${tmp}/ack.log" || fail "no marco el duplicado"

# precontest (macro): lock + usb block
rm -rf "${state}"; mkdir -p "${state}"
IFS='|' read -r P S <<< "$(mk_cmd precontest)"; write_curl "${P}" "${S}"
: > "${actions}"
run
grep -qx 'contest-session lock' "${actions}" || fail "precontest no bloqueo la sesion"
grep -qx 'usb block' "${actions}" || fail "precontest no bloqueo USB"

# firma invalida -> no ejecuta
rm -rf "${state}"; mkdir -p "${state}"
IFS='|' read -r P S <<< "$(mk_cmd message)"
write_curl "${P}" "$(printf '%s' "${S}" | tr 'A-Za-z' 'N-ZA-Mn-za-m')"
: > "${actions}"
run
[ -s "${actions}" ] && fail "ejecuto un comando con firma invalida"
[ -f "${state}/applied/N1" ] && fail "marco aplicado un comando con firma invalida"

echo "PASS: contest-control"
