#!/usr/bin/env bash
# Wifi PCI que no levanta el link en frio: unbind + PCI reset + rebind antes
# de que arranque NetworkManager. El script y la unit llegan por overlay/.
set -euo pipefail

chmod 0755 /usr/local/sbin/contest-wifi-pci-reset.sh
systemctl enable contest-wifi-pci-reset.service
