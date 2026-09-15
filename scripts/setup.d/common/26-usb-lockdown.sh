#!/usr/bin/env bash
# Bloqueo de almacenamiento externo. El script y la unit llegan por overlay/.
set -euo pipefail

install -d -o root -g root -m 0755 /etc/contestiso
chmod 0755 /usr/local/sbin/contest-usb-storage.sh

want="${USB_STORAGE_DEFAULT:-blocked}"
printf 'USB_STORAGE=%s\n' "${want}" > /etc/contestiso/usb-policy.env
chmod 0644 /etc/contestiso/usb-policy.env

if [ "${want}" = "allowed" ]; then
    rm -f /etc/modprobe.d/contest-usb-storage.conf
else
    cat > /etc/modprobe.d/contest-usb-storage.conf <<'EOF'
install usb_storage /bin/true
install uas /bin/true
EOF
fi

systemctl enable contest-usb-policy.service
systemctl enable contest-usb-reload.timer
