#!/usr/bin/env bash

set -euo pipefail

unit_file="/lib/systemd/system/atd.service"
if [ -f "/usr/lib/systemd/system/atd.service" ]; then
    unit_file="/usr/lib/systemd/system/atd.service"
fi

# Mantener instalado el paquete at, pero desactivar su arranque automático en la imagen.
rm -f /etc/systemd/system/multi-user.target.wants/atd.service

cat > "${unit_file}" <<'EOM'
[Unit]
Description=Deferred execution scheduler
Documentation=man:atd(8)
After=remote-fs.target nss-user-lookup.target

[Service]
ExecStartPre=-find /var/spool/cron/atjobs -type f -name "=*" -not -newercc /run/systemd -delete
ExecStart=/usr/sbin/atd -f -l 5 -b 30
IgnoreSIGPIPE=false
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOM

chmod 644 "${unit_file}"
