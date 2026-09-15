#!/usr/bin/env bash

set -euo pipefail

DEFAULT_USER_VAL="${DEFAULT_USER}"
OPT_DIR="${OPT_CONTEST_DIR}"
user_home="$(getent passwd "${DEFAULT_USER_VAL}" | cut -d: -f6)"

mkdir -p \
    /etc/skel/.config \
    /etc/skel/Desktop \
    /etc/xdg/autostart \
    "${user_home}/Desktop"

echo yes > /etc/skel/.config/gnome-initial-setup-done

# Escritorio: solo el lanzador "Documentación" (desktop-icons-ng lo ancla a la
# esquina inferior derecha, ver 14-gnome-defaults.sh). El resto de apps van en
# el dash. gnome-session moderno solo lee /etc/xdg/autostart (no
# /usr/share/gnome/autostart): ahi arranca el login zenity del concurso.
install -m 644 "${OPT_DIR}/misc/desktop-gnome-autostart.desktop" /etc/xdg/autostart/desktop-gnome-autostart.desktop
# Lanzador "Llamar al staff" para el dash (favorite-apps de 14-gnome-defaults.sh).
install -m 644 "${OPT_DIR}/misc/contest-call-staff.desktop" /usr/share/applications/contest-call-staff.desktop
# Lanzador "Documentación" en el escritorio. En /etc/skel para que sobreviva a
# "limpiar home" (que recopia /etc/skel) y en el home ya creado del usuario.
# 0755: desktop-icons-ng exige el bit +x (si no, "archivo .desktop roto").
install -m 0755 "${OPT_DIR}/misc/desktop-home.desktop" /etc/skel/Desktop/documentacion.desktop
install -m 0755 "${OPT_DIR}/misc/desktop-home.desktop" "${user_home}/Desktop/documentacion.desktop"
# En cada login marca los .desktop del escritorio como confiables (el bit +x no
# alcanza: DING tambien pide metadata::trusted, y reset-home borra ese metadata).
cat > /etc/xdg/autostart/contest-trust-desktop.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Confiar en lanzadores del escritorio
Exec=/usr/local/bin/contest-trust-desktop.sh
NoDisplay=true
X-GNOME-Autostart-Phase=Applications
OnlyShowIn=GNOME;
EOF

cat >> /etc/skel/.bashrc <<EOF_BASHRC

# Herramientas del concurso ICPC Bolivia
export PATH="\${PATH}:${OPT_DIR}/bin"
EOF_BASHRC

cat > /etc/profile.d/icpc.sh <<EOF_PROFILE
export PATH="\${PATH}:${OPT_DIR}/bin"
EOF_PROFILE

chown -R "${DEFAULT_USER_VAL}:${DEFAULT_USER_VAL}" "${user_home}/.config" "${user_home}/Desktop"
