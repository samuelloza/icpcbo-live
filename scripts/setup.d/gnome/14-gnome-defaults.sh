#!/usr/bin/env bash

set -euo pipefail

OPT_DIR="${OPT_CONTEST_DIR}"

mkdir -p /etc/dconf/profile
cat > /etc/dconf/profile/user <<'EOF'
user-db:user
system-db:local
EOF

# Base de datos dconf del sistema: valores por defecto para el concursante
mkdir -p /etc/dconf/db/local.d
cat > /etc/dconf/db/local.d/20-contestant-defaults <<'EOF'
[org/gnome/shell]
enabled-extensions=['stealmyfocus-ext', 'ding@rastersoft.com']
disable-user-extensions=false
favorite-apps=['firefox-esr.desktop', 'code.desktop', 'sublime_text.desktop', 'geany.desktop', 'intellij_idea_community.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop', 'contest-call-staff.desktop']

# Iconos de escritorio (desktop-icons-ng): solo el lanzador "Documentación",
# anclado a la esquina inferior derecha. Sin carpeta personal, papelera ni
# volumenes montados (el USB/ISO del instalador NO debe aparecer).
[org/gnome/shell/extensions/ding]
show-home=false
show-trash=false
show-volumes=false
show-network-volumes=false
show-drop-place=false
start-corner='bottom-right'
icon-size='standard'
show-link-emblem=false

EOF

cat >> /etc/dconf/db/local.d/20-contestant-defaults <<EOF

[org/gnome/desktop/input-sources]
sources=${GNOME_INPUT_SOURCES}
per-window=false

EOF

cat >> /etc/dconf/db/local.d/20-contestant-defaults <<EOF

# El equipo no debe apagar pantalla, bloquearse ni suspender NUNCA.
[org/gnome/desktop/session]
idle-delay=uint32 0

[org/gnome/desktop/screensaver]
lock-enabled=false
idle-activation-enabled=false

[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
sleep-inactive-ac-timeout=0
sleep-inactive-battery-timeout=0
power-button-action='nothing'
idle-dim=false

[org/gnome/desktop/wm/preferences]
button-layout='appmenu:minimize,maximize,close'

[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='Adwaita-dark'

[org/gnome/desktop/background]
picture-uri='file://${OPT_DIR}/misc/desktop-wallpaper.svg'
picture-uri-dark='file://${OPT_DIR}/misc/desktop-wallpaper.svg'
picture-options='centered'
primary-color='#000000'
secondary-color='#000000'
EOF

dconf update || true
