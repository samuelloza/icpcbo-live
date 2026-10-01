#!/usr/bin/env bash
# Bluetooth apagado por defecto: no instalamos bluez, pero el kernel puede
# autocargar btusb/btintel/etc al detectar el chip. Se bloquea el modulo
# core 'bluetooth' del que todos dependen, igual que USB_STORAGE bloquea
# usb_storage/uas en 26-usb-lockdown.sh.
set -euo pipefail

cat > /etc/modprobe.d/contest-bluetooth.conf <<'EOF'
install bluetooth /bin/true
EOF
