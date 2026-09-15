#!/usr/bin/env bash
# Apaga servicios de escritorio inutiles en un equipo de concurso que ademas
# ensucian el journal:
#   - tracker / localsearch: indexa /home y falla en overlay ("Operation not
#     supported"), repetido en cada arranque.
#   - KDE Connect: descubrimiento por broadcast/mDNS, siempre bloqueado por el
#     lockdown de red.
set -euo pipefail

# Unidades de usuario (systemd --user): enmascaradas globalmente.
for u in tracker-miner-fs-3.service tracker-extract-3.service tracker-miner-rss-3.service \
         localsearch-3.service localsearch-extractor-3.service \
         evolution-source-registry.service geoclue.service; do
    systemctl --global mask "${u}" 2>/dev/null || true
done

# Autostarts XDG: un .desktop con Hidden=true en /etc/xdg/autostart tapa al
# mismo nombre de /usr/share/... y de los paquetes.
mkdir -p /etc/xdg/autostart
for app in tracker-miner-fs-3 tracker-extract-3 localsearch-3 \
           org.kde.kdeconnect.daemon org.gnome.Evolution-alarm-notify \
           org.gnome.Software geoclue-demo-agent; do
    cat > "/etc/xdg/autostart/${app}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${app} (desactivado para el concurso)
Exec=/bin/true
Hidden=true
X-GNOME-Autostart-enabled=false
NoDisplay=true
EOF
done
