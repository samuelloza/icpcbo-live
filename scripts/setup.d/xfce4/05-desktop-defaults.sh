#!/usr/bin/env bash

set -euo pipefail

mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml
cat > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adwaita-dark"/>
    <property name="IconThemeName" type="string" value="Adwaita"/>
  </property>
</channel>
XML

cat > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-power-manager" version="1.0">
  <property name="xfce4-power-manager" type="empty">
    <property name="blank-on-ac" type="int" value="15"/>
    <property name="dpms-enabled" type="bool" value="true"/>
    <property name="show-tray-icon" type="bool" value="false"/>
  </property>
</channel>
XML
