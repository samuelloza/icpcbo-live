#!/usr/bin/env bash
# Recoge las peticiones de "llamar al staff" del buzon y las reporta al panel
# del coordinador via contest-alert.sh. Lo dispara contest-call-staff.path.
set -euo pipefail

DROP="${CONTEST_CALL_STAFF_DIR:-/run/contest-call-staff}"
shopt -s nullglob

for f in "${DROP}"/req-*; do
    note="$(head -c 200 "${f}" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    rm -f "${f}"
    /usr/local/sbin/contest-alert.sh help.requested "${note:-sin detalle}" || true
done
