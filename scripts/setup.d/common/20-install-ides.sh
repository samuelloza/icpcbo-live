#!/usr/bin/env bash

set -euo pipefail

CACHE_DIR="/tmp/cache/ides"
ECLIPSE_CPP_VERSION="2025-03"
KOTLIN_COMPILER_VERSION="1.9.24"
INTELLIJ_IDEA_VERSION="2024.2.3"

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

# Compilador de Kotlin
KOTLIN_COMPILER_URL="https://github.com/JetBrains/kotlin/releases/download/v${KOTLIN_COMPILER_VERSION}/kotlin-compiler-${KOTLIN_COMPILER_VERSION}.zip"
KOTLIN_COMPILER_DST="/opt/kotlinc-${KOTLIN_COMPILER_VERSION}"
if [ ! -d "${KOTLIN_COMPILER_DST}" ]; then
    if /tmp/cached-curl.sh "${KOTLIN_COMPILER_URL}" "${CACHE_DIR}/kotlin-compiler.zip"; then
        rm -rf /opt/kotlinc
        unzip -q "${CACHE_DIR}/kotlin-compiler.zip" -d /opt
        if [ -d /opt/kotlinc ]; then
            mv /opt/kotlinc "${KOTLIN_COMPILER_DST}"
            ln -sfn "${KOTLIN_COMPILER_DST}" /opt/kotlinc
            ln -sfn "${KOTLIN_COMPILER_DST}/bin/kotlinc" /usr/local/bin/kotlinc
            ln -sfn "${KOTLIN_COMPILER_DST}/bin/kotlin" /usr/local/bin/kotlin
        fi
    else
        echo "W: Kotlin compiler download failed" >&2
    fi
fi

# IntelliJ IDEA Community
# Entorno de desarrollo oficial de Kotlin usado en entornos tipo ICPC
INTELLIJ_ARCHIVE="ideaIC-${INTELLIJ_IDEA_VERSION}.tar.gz"
INTELLIJ_URL="https://download.jetbrains.com/idea/${INTELLIJ_ARCHIVE}"
INTELLIJ_DIR="/opt/intellij-idea-community"
if [ ! -d "${INTELLIJ_DIR}" ]; then
    if /tmp/cached-curl.sh "${INTELLIJ_URL}" "${CACHE_DIR}/${INTELLIJ_ARCHIVE}"; then
        extracted_root="$(
            python3 - "${CACHE_DIR}/${INTELLIJ_ARCHIVE}" <<'PY'
import sys
import tarfile

with tarfile.open(sys.argv[1], "r:gz") as archive:
    for member in archive:
        root = member.name.split("/", 1)[0].strip()
        if root:
            print(root)
            break
PY
        )"
        tar -zxf "${CACHE_DIR}/${INTELLIJ_ARCHIVE}" -C /opt
        if [ -n "${extracted_root}" ] && [ -d "/opt/${extracted_root}" ]; then
            rm -rf "${INTELLIJ_DIR}"
            mv "/opt/${extracted_root}" "${INTELLIJ_DIR}"
            ln -sfn "${INTELLIJ_DIR}/bin/idea.sh" /usr/local/bin/idea
            [ -f "${INTELLIJ_DIR}/bin/idea.png" ] && \
                cp "${INTELLIJ_DIR}/bin/idea.png" /usr/share/pixmaps/intellij-idea.png

            cat > /usr/share/applications/intellij_idea_community.desktop <<'EOF'
[Desktop Entry]
Name=IntelliJ IDEA Community
Exec=/opt/intellij-idea-community/bin/idea.sh
Type=Application
Icon=intellij-idea
Categories=Development;IDE;
Terminal=false
EOF
        fi
    else
        echo "W: IntelliJ IDEA Community download failed" >&2
    fi
fi

rm -rf "${CACHE_DIR}"
