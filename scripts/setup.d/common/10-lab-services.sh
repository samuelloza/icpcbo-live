#!/usr/bin/env bash
# Prepara los servicios de despliegue del laboratorio que corren en el sistema en vivo.
# - contest-full-install.service : instalación completa a disco
#   (unsquashfs + GRUB) con contest.install_mode=full
# - contest-deploy.service       : instalación por overlay
#   (copia del squashfs) en el primer arranque del ISO

set -euo pipefail

cat > /etc/systemd/system/stats-report.timer <<TIMER
[Unit]
Description=Run stats report every ${STATS_REPORT_INTERVAL}

[Timer]
OnBootSec=${STATS_REPORT_ON_BOOT}
OnUnitActiveSec=${STATS_REPORT_INTERVAL}
Persistent=true
Unit=stats-report.service

[Install]
WantedBy=timers.target
TIMER

systemctl enable contest-full-install.service
systemctl enable contest-deploy.service
systemctl enable contest-overlay-provision.service
systemctl enable contest-update.service
systemctl enable stats-report.timer
