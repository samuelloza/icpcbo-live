#!/usr/bin/env bash

set -euo pipefail

DEFAULT_USER_VAL="${DEFAULT_USER}"
OPT_DIR="${OPT_CONTEST_DIR}"
user_home="$(getent passwd "${DEFAULT_USER_VAL}" | cut -d: -f6)"

mkdir -p \
    /etc/skel/.config/Code/User \
    /etc/skel/Desktop \
    /usr/share/gnome/autostart \
    "${user_home}/.config/Code/User" \
    "${user_home}/Desktop"

echo yes > /etc/skel/.config/gnome-initial-setup-done

cat > /etc/skel/.config/Code/User/settings.json <<'EOM'
{
    "C_Cpp.default.cppStandard": "gnu++20",
    "editor.fontSize": 14,
    "editor.tabSize": 4,
    "editor.insertSpaces": true,
    "terminal.integrated.fontSize": 13
}
EOM

install -m 755 "${OPT_DIR}/misc/desktop-home.desktop" /etc/skel/Desktop/desktop-home.desktop
install -m 755 /usr/share/applications/gnome-keyboard-panel.desktop /etc/skel/Desktop/gnome-keyboard-panel.desktop
install -m 644 "${OPT_DIR}/misc/desktop-gnome-autostart.desktop" /usr/share/gnome/autostart/desktop-gnome-autostart.desktop

cat >> /etc/skel/.bashrc <<EOF_BASHRC

# Herramientas del concurso ICPC Bolivia
export PATH="\${PATH}:${OPT_DIR}/bin"
EOF_BASHRC

cat > /etc/profile.d/icpc.sh <<EOF_PROFILE
export PATH="\${PATH}:${OPT_DIR}/bin"
EOF_PROFILE

cp /etc/skel/.config/Code/User/settings.json "${user_home}/.config/Code/User/"
install -m 755 "${OPT_DIR}/misc/desktop-home.desktop" "${user_home}/Desktop/desktop-home.desktop"
install -m 755 /usr/share/applications/gnome-keyboard-panel.desktop "${user_home}/Desktop/gnome-keyboard-panel.desktop"
chown -R "${DEFAULT_USER_VAL}:${DEFAULT_USER_VAL}" "${user_home}/.config" "${user_home}/Desktop"
