#!/usr/bin/env bash
# El equipo NO debe suspender / hibernar / apagar la pantalla NUNCA.
#   1. systemd: enmascara los targets de sleep -> nada puede suspender, ni
#      GNOME, ni logind, ni un 'systemctl suspend' suelto.
#   2. logind: ignora la tapa del portatil y las teclas de energia.
# La capa GNOME (dconf power/screensaver) va en gnome/14-gnome-defaults.sh.
set -euo pipefail

for t in sleep.target suspend.target hibernate.target hybrid-sleep.target; do
    ln -sf /dev/null "/etc/systemd/system/${t}"
done

install -d -m 0755 /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/10-no-suspend.conf <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
HandlePowerKey=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
IdleAction=ignore
EOF
