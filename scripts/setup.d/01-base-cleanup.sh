#!/usr/bin/env bash

set -euo pipefail

for pkg in snapd gnome-software-plugin-snap cloud-init popularity-contest; do
    if dpkg-query -W -f='${Status}\n' "${pkg}" 2>/dev/null | grep -q 'install ok installed'; then
        apt-get purge -y "${pkg}"
    fi
done

apt-get autoremove -y --purge || true

if [[ -f /etc/environment ]]; then
    sed -i 's#:/snap/bin##g; s#:/var/lib/snapd/snap/bin##g' /etc/environment
fi

rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd
rm -rf /home/*/snap 2>/dev/null || true
rm -f /etc/profile.d/apps-bin-path.sh 2>/dev/null || true
