#!/usr/bin/env bash

set -euo pipefail

mkdir -p /etc/apt/apt.conf.d
mkdir -p /etc/apt/preferences.d

cat > /etc/apt/apt.conf.d/10periodic <<'EOF_APT_10'
APT::Periodic::Update-Package-Lists "14";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "0";
EOF_APT_10

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF_APT_20'
APT::Periodic::Update-Package-Lists "14";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "0";
EOF_APT_20

cat > /etc/apt/preferences.d/99-nosnap <<'EOF_APT_NOSNAP'
Package: snapd
Pin: release *
Pin-Priority: -1

Package: gnome-software-plugin-snap
Pin: release *
Pin-Priority: -1
EOF_APT_NOSNAP
