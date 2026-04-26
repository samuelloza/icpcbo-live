#!/usr/bin/env bash
# Prepares the lab deployment services that run in the live system.
# - contest-full-install.service : full disk install (unsquashfs + GRUB) on contest.install_mode=full
# - contest-deploy.service       : overlay install (squashfs copy) on first ISO boot

set -euo pipefail

systemctl enable contest-full-install.service
systemctl enable contest-deploy.service
systemctl enable contest-overlay-provision.service
systemctl enable contest-update.service
