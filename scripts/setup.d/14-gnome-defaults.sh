#!/usr/bin/env bash

set -euo pipefail

GNOME_INPUT_SOURCES_VAL="${GNOME_INPUT_SOURCES:-[('xkb', 'latam'), ('xkb', 'us')]}"
OPT_DIR="${OPT_CONTEST_DIR:-/opt/icpc}"

# Configure dconf system profile so GNOME reads the system-db
mkdir -p /etc/dconf/profile
cat > /etc/dconf/profile/user <<'EOF'
user-db:user
system-db:local
EOF

# System dconf database: contestant defaults
mkdir -p /etc/dconf/db/local.d
cat > /etc/dconf/db/local.d/20-contestant-defaults <<'EOF'
[org/gnome/shell]
enabled-extensions=['stealmyfocus-ext']
disable-user-extensions=false
favorite-apps=['firefox-esr.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop']

EOF

cat >> /etc/dconf/db/local.d/20-contestant-defaults <<EOF

[org/gnome/desktop/input-sources]
sources=${GNOME_INPUT_SOURCES_VAL}
per-window=false

EOF

cat >> /etc/dconf/db/local.d/20-contestant-defaults <<EOF

[org/gnome/desktop/session]
idle-delay=uint32 900

[org/gnome/desktop/screensaver]
lock-enabled=true
lock-delay=uint32 30

[org/gnome/desktop/background]
picture-uri='file://${OPT_DIR}/misc/icpcbo-wallpaper.png'
picture-uri-dark='file://${OPT_DIR}/misc/icpcbo-wallpaper.png'
picture-options='centered'
primary-color='#000000'
secondary-color='#000000'
EOF

dconf update || true
