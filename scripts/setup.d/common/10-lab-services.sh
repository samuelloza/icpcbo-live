#!/usr/bin/env bash
# Prepara únicamente los servicios del sistema completo

set -euo pipefail

systemctl enable contest-overlay-provision.service
systemctl enable contest-call-staff.path
