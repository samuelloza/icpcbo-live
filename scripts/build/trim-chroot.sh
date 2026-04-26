#!/usr/bin/env bash

set -euo pipefail

# Read packages to remove line by line to avoid word-splitting on the list.
REMOVE_PKGS=()
while IFS= read -r pkg; do
    case "${pkg}" in
        ""|\#*)
            continue
            ;;
    esac
    REMOVE_PKGS+=("${pkg}")
done < /tmp/packages-remove.list

if [ "${#REMOVE_PKGS[@]}" -gt 0 ]; then
    apt-get purge -y "${REMOVE_PKGS[@]}" || true
fi

apt-get autoremove -y --purge || true

rm -f /etc/apt/apt.conf.d/01proxy || true
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /var/log/*
rm -rf /tmp/* /var/tmp/*
