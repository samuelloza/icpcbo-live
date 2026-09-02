#!/usr/bin/env bash
# Estabilidad en equipos de 4 GB: swap comprimido en RAM (zram) para dar
# holgura de memoria, y earlyoom para que la presion mate un proceso antes
# de que el kernel entre en thrashing y el equipo se congele.
set -euo pipefail

apt-get install -y --no-install-recommends systemd-zram-generator earlyoom

# zram = min(RAM, 4 GiB), comprimido con zstd. En una maquina de 4 GB da
# ~4 GiB de swap que en RAM real ocupa ~1.5-2 GiB.
cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram, 4096)
compression-algorithm = zstd
EOF

# Con swap en zram conviene swappear agresivo y sin readahead.
cat > /etc/sysctl.d/90-low-ram.conf <<'EOF'
vm.swappiness = 180
vm.page-cluster = 0
EOF

systemctl enable earlyoom.service
