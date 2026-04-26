#!/usr/bin/env bash

set -euo pipefail

mkdir -p /etc/dconf/db/local.d
cat > /etc/dconf/db/local.d/10-desktop-defaults <<'EOF_DCONF'
[org/gnome/shell]
disable-user-extensions=true
EOF_DCONF

dconf update 2>/dev/null || true
