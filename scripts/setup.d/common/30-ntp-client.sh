#!/usr/bin/env bash
# Cliente NTP del concurso: sincroniza SOLO contra NET_NTP_SERVERS (o
# NET_DNS_SERVERS si aquel esta vacio; suele ser el mismo host que corre
# control-server/docker-compose.yml -> servicio 'ntp').
#
# Sin esto, systemd-timesyncd usa el pool de Debian y el bloqueo de red tira
# esos paquetes (drops a :123 en el journal); el reloj no sincroniza y la
# validacion TLS del login puede fallar.
set -euo pipefail

srv="${NET_NTP_SERVERS:-${NET_DNS_SERVERS:-}}"
if [ -z "${srv}" ]; then
    echo "sin NET_NTP_SERVERS ni NET_DNS_SERVERS: se deja timesyncd por defecto"
    exit 0
fi

install -d -m 0755 /etc/systemd/timesyncd.conf.d
cat > /etc/systemd/timesyncd.conf.d/10-contest.conf <<EOF
[Time]
NTP=${srv}
FallbackNTP=
EOF

# El .service viene con el paquete; en chroot hay que habilitarlo a mano.
systemctl enable systemd-timesyncd.service 2>/dev/null || true
