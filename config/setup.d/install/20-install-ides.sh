#!/usr/bin/env bash

set -euo pipefail
exit
CACHE_DIR="/tmp/cache/ides"
ECLIPSE_CPP_VERSION="2025-03"
ECLIPSE_INSTALLER_VERSION="2025-06"

mkdir -p "${CACHE_DIR}"

# Sublime Text
if ! command -v subl >/dev/null 2>&1; then
    if /tmp/cached-curl.sh https://download.sublimetext.com/sublimehq-pub.gpg \
            /tmp/sublimehq.gpg 2>/dev/null; then
        gpg --dearmor < /tmp/sublimehq.gpg \
            > /usr/share/keyrings/sublimehq-archive-keyring.gpg
        rm -f /tmp/sublimehq.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/sublimehq-archive-keyring.gpg] \
https://download.sublimetext.com/ apt/stable/" \
            > /etc/apt/sources.list.d/sublime-text.list
        apt-get update -qq
        apt-get install -y sublime-text || echo "W: Sublime Text install failed" >&2
    else
        echo "W: Failed to fetch Sublime Text GPG key, skipping" >&2
    fi
fi

# Eclipse C/C++
ECLIPSE_CPP_NAME="eclipse-cpp-${ECLIPSE_CPP_VERSION}-R-linux-gtk-x86_64"
ECLIPSE_CPP_URL="https://archive.eclipse.org/technology/epp/downloads/release/${ECLIPSE_CPP_VERSION}/R/${ECLIPSE_CPP_NAME}.tar.gz"
if [ ! -d /opt/eclipse ]; then
    if /tmp/cached-curl.sh "${ECLIPSE_CPP_URL}" "${CACHE_DIR}/eclipse-cpp.tar.gz"; then
        tar -zxf "${CACHE_DIR}/eclipse-cpp.tar.gz" -C /opt
        if [ -d /opt/eclipse ]; then
            icon_src="$(find /opt/eclipse/plugins -name 'eclipse*.png' 2>/dev/null | head -1)"
            [ -n "${icon_src}" ] && cp "${icon_src}" /usr/share/pixmaps/eclipse-cpp.png

            if [ -f /opt/eclipse/eclipse.ini ]; then
                grep -q 'org.eclipse.oomph.setup.donate' /opt/eclipse/eclipse.ini || \
                    sed -i '/^-vmargs/a -Dorg.eclipse.oomph.setup.donate=false' \
                        /opt/eclipse/eclipse.ini
            fi

            cat > /usr/share/applications/eclipse_cpp.desktop <<'EOF'
[Desktop Entry]
Name=Eclipse C/C++
Exec=/opt/eclipse/eclipse
Type=Application
Icon=eclipse-cpp
Categories=Development;IDE;
Terminal=false
EOF
        fi
    else
        echo "W: Eclipse C++ download failed" >&2
    fi
fi

# Eclipse Installer (Java IDE setup)
ECLIPSE_INST_URL="https://download.eclipse.org/oomph/products/latest/eclipse-inst-jre-linux64.tar.gz"
                  
if [ ! -d /opt/eclipse-installer-java ]; then
    if /tmp/cached-curl.sh "${ECLIPSE_INST_URL}" "${CACHE_DIR}/eclipse-installer.tar.gz"; then
        tar -zxf "${CACHE_DIR}/eclipse-installer.tar.gz" -C /opt
        if [ -d /opt/eclipse-installer ]; then
            mv /opt/eclipse-installer /opt/eclipse-installer-java
            icon_src="$(find /opt/eclipse-installer-java \
                -name '*.xpm' -o -name 'icon*.png' 2>/dev/null | head -1)"
            [ -n "${icon_src}" ] && cp "${icon_src}" /usr/share/pixmaps/eclipse-installer.png

            cat > /usr/share/applications/eclipse_installer.desktop <<'EOF'
[Desktop Entry]
Name=Eclipse Installer (Java)
Exec=/opt/eclipse-installer-java/eclipse-inst
Type=Application
Icon=eclipse-installer
Categories=Development;IDE;
Terminal=false
EOF
        fi
    else
        echo "W: Eclipse Installer download failed" >&2
    fi
fi

rm -rf "${CACHE_DIR}"
