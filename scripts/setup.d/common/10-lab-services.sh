#!/usr/bin/env bash
# Prepara únicamente los servicios del sistema completo

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

systemctl enable contest-overlay-provision.service
systemctl enable contest-update.service
systemctl enable stats-report.timer
