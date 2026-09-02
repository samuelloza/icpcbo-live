#!/usr/bin/env bash
# minbase deja default.target = multi-user.target: sin esto el gestor de
# pantalla (gdm3 / lightdm) nunca arranca y el equipo queda en un login de
# texto. También asegura que el DM esté habilitado (su postinst suele hacerlo,
# pero en chroot no siempre).
set -euo pipefail

systemctl set-default graphical.target

for dm in gdm3 lightdm; do
    for base in /lib/systemd/system /usr/lib/systemd/system; do
        if [ -e "${base}/${dm}.service" ]; then
            systemctl enable "${dm}.service" 2>/dev/null || true
        fi
    done
done

# display-manager.service es un alias al DM instalado; si falta, forzarlo.
if [ ! -e /etc/systemd/system/display-manager.service ]; then
    if [ -e /lib/systemd/system/gdm3.service ] || [ -e /usr/lib/systemd/system/gdm3.service ]; then
        ln -sf /lib/systemd/system/gdm3.service /etc/systemd/system/display-manager.service
    elif [ -e /lib/systemd/system/lightdm.service ] || [ -e /usr/lib/systemd/system/lightdm.service ]; then
        ln -sf /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service
    fi
fi
