#!/usr/bin/env bash

set -euo pipefail

OPT_DIR="${OPT_CONTEST_DIR}"

# Configura el perfil de sistema de dconf para que GNOME lea la base de datos del sistema
mkdir -p /etc/dconf/profile
cat > /etc/dconf/profile/user <<'EOF'
user-db:user
system-db:local
EOF

# Base de datos dconf del sistema: valores por defecto para el concursante
mkdir -p /etc/dconf/db/local.d
cat > /etc/dconf/db/local.d/20-contestant-defaults <<'EOF'
[org/gnome/shell]
enabled-extensions=['stealmyfocus-ext']
disable-user-extensions=false
favorite-apps=['firefox-esr.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop']

EOF

cat >> /etc/dconf/db/local.d/20-contestant-defaults <<EOF

[org/gnome/desktop/input-sources]
sources=${GNOME_INPUT_SOURCES}
per-window=false

EOF

cat >> /etc/dconf/db/local.d/20-contestant-defaults <<EOF

[org/gnome/desktop/session]
idle-delay=uint32 900

[org/gnome/desktop/screensaver]
lock-enabled=true
lock-delay=uint32 30

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
