#!/usr/bin/env bash
# Bloqueo de red: nftables con salida denegada por defecto + allowlist. Los
# archivos (nftables.conf, script y units) llegan por overlay/. Este hook solo
# escribe la config de sitio y habilita los servicios.
set -euo pipefail

install -d -o root -g root -m 0755 /etc/contestiso
chmod 0755 /usr/local/sbin/contest-allowlist-apply.sh

{
    printf 'NET_LOCKDOWN=%q\n' "${NET_LOCKDOWN:-true}"
    printf 'NET_DNS_SERVERS=%q\n' "${NET_DNS_SERVERS:-}"
    printf 'NET_NTP_SERVERS=%q\n' "${NET_NTP_SERVERS:-}"
} > /etc/contestiso/netlockdown.env
chmod 0644 /etc/contestiso/netlockdown.env

if [ "${NET_LOCKDOWN:-true}" != "true" ]; then
    systemctl disable nftables.service contest-allowlist.service contest-allowlist.timer 2>/dev/null || true
    echo "NET_LOCKDOWN != true: bloqueo de red no se activa"
    exit 0
fi

# Lista inicial: hosts de los servicios del concurso + NET_ALLOW_HOSTS.
service_hosts="$(python3 - \
    "${AUTH_SERVICE_URL:-}" \
    "${CONTROL_SERVICE_URL:-}" "${PULSO_PUSHGATEWAY_URL:-}" <<'PY'
import sys, urllib.parse
seen = []
for raw in sys.argv[1:]:
    host = urllib.parse.urlparse(raw).hostname if raw else None
    if host and host not in seen:
        seen.append(host)
print("\n".join(seen))
PY
)"

{
    echo "# Hosts/IPs que las maquinas del concurso pueden alcanzar (uno por linea)."
    echo "# '#' = comentario. El coordinador lo regenera con la accion set-allowlist."
    printf '%s\n' ${service_hosts}
    for h in ${NET_ALLOW_HOSTS:-}; do printf '%s\n' "${h}"; done
} > /etc/contestiso/allowlist.conf
chmod 0644 /etc/contestiso/allowlist.conf

# Canal de control: estos hosts SIEMPRE quedan permitidos. set-allowlist solo
# reescribe allowlist.conf, nunca este archivo, asi una allowlist mala enviada
# desde el panel no puede aislar a la maquina del control-server.
{
    echo "# Hosts del canal de control (control-server, login, pulso, updates)."
    echo "# set-allowlist NO borra esto. Se regenera al re-buildear la ISO."
    printf '%s\n' ${service_hosts}
} > /etc/contestiso/allowlist.base
chmod 0644 /etc/contestiso/allowlist.base

systemctl enable nftables.service contest-allowlist.service contest-allowlist.timer

# fwupd trata de bajar metadata de firmware (LVFS, en Fastly) y el lockdown lo
# bloquea: solo genera 'contest-drop' y 'fwupd-refresh.service failed' en el log.
systemctl disable fwupd-refresh.timer 2>/dev/null || true
systemctl mask fwupd-refresh.service 2>/dev/null || true
