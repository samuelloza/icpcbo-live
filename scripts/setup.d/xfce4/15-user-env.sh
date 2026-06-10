#!/usr/bin/env bash

set -euo pipefail

DEFAULT_USER_VAL="${DEFAULT_USER}"
OPT_DIR="${OPT_CONTEST_DIR}"
WALLPAPER="${OPT_DIR}/misc/desktop-wallpaper.svg"
user_home="$(getent passwd "${DEFAULT_USER_VAL}" | cut -d: -f6)"

mkdir -p \
    /etc/skel/.config/Code/User \
    /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml \
    /etc/skel/Desktop \
    /etc/xdg/autostart \
    "${user_home}/.config/Code/User" \
    "${user_home}/.config/xfce4/xfconf/xfce-perchannel-xml" \
    "${user_home}/Desktop"

cat > /etc/skel/.config/Code/User/settings.json <<'EOM'
{
    "C_Cpp.default.cppStandard": "gnu++20",
    "editor.fontSize": 14,
    "editor.tabSize": 4,
    "editor.insertSpaces": true,
    "terminal.integrated.fontSize": 13
}
EOM

cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml <<'EOF_XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adwaita-dark"/>
    <property name="IconThemeName" type="string" value="Adwaita"/>
  </property>
</channel>
EOF_XML

cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml <<EOF_XML
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="image-path" type="string" value="${WALLPAPER}"/>
        <property name="image-style" type="int" value="3"/>
      </property>
    </property>
  </property>
</channel>
EOF_XML

ln -sfn /usr/share/doc/contest/index.html "/etc/skel/Desktop/Inicio.html"
install -m 755 /usr/share/applications/xfce-keyboard-settings.desktop /etc/skel/Desktop/xfce-keyboard-settings.desktop
install -m 644 "${OPT_DIR}/misc/desktop-xfce-autostart.desktop" /etc/xdg/autostart/desktop-xfce-autostart.desktop

cat >> /etc/skel/.bashrc <<EOF_BASHRC

# Herramientas del concurso ICPC Bolivia
export PATH="\${PATH}:${OPT_DIR}/bin"
EOF_BASHRC

cat > /etc/profile.d/icpc.sh <<EOF_PROFILE
export PATH="\${PATH}:${OPT_DIR}/bin"
EOF_PROFILE

cp /etc/skel/.config/Code/User/settings.json "${user_home}/.config/Code/User/"
cp /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml "${user_home}/.config/xfce4/xfconf/xfce-perchannel-xml/"
cp /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml "${user_home}/.config/xfce4/xfconf/xfce-perchannel-xml/"
ln -sfn /usr/share/doc/contest/index.html "${user_home}/Desktop/Inicio.html"
install -m 755 /usr/share/applications/xfce-keyboard-settings.desktop "${user_home}/Desktop/xfce-keyboard-settings.desktop"
chown -R "${DEFAULT_USER_VAL}:${DEFAULT_USER_VAL}" "${user_home}/.config" "${user_home}/Desktop"
chown -h "${DEFAULT_USER_VAL}:${DEFAULT_USER_VAL}" "${user_home}/Desktop/Inicio.html"

checksum="$(sha256sum "${user_home}/Desktop/xfce-keyboard-settings.desktop" | awk '{print $1}')"
runuser -u "${DEFAULT_USER_VAL}" -- env HOME="${user_home}" dbus-run-session \
    gio set -t string "${user_home}/Desktop/xfce-keyboard-settings.desktop" metadata::xfce-exe-checksum "${checksum}" || true
