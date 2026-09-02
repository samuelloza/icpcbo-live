#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local label="$3"

    if [[ "${actual}" != "${expected}" ]]; then
        fail "${label}: expected '${expected}', got '${actual}'"
    fi
}

assert_file() {
    local path="$1"

    [[ -f "${PROJECT_DIR}/${path}" ]] || fail "missing file: ${path}"
}

assert_executable() {
    local path="$1"

    [[ -x "${PROJECT_DIR}/${path}" ]] || fail "file is not executable: ${path}"
}

assert_package() {
    local pkg="$1"

    grep -qxF "${pkg}" "${PROJECT_DIR}/scripts/setup.d/gnome/packages.list" || \
        fail "missing package in scripts/setup.d/gnome/packages.list: ${pkg}"
}

unset ISO_NAME
unset DEBIAN_SUITE
unset META_DISTRO_ID
unset META_DISTRO_NAME
unset META_DISTRO_VERSION
unset CONTEST_DIR
unset HOSTNAME
unset SUPPORTED_LOCALES
unset DOWNLOAD_CONNECTIONS
unset OUTPUT_RUNTIME
unset DESKTOP_PROFILE
unset ISO_PATH
unset APT_PROXY

# shellcheck source=/dev/null
source "${PROJECT_DIR}/config/iso.conf"

assert_equals "icpc-bolivia-debian" "${ISO_NAME}" "ISO_NAME"
assert_equals "trixie" "${DEBIAN_SUITE}" "DEBIAN_SUITE"
assert_equals "icpc-bolivia-debian" "${META_DISTRO_ID}" "META_DISTRO_ID"
assert_equals "ICPC Bolivia Debian" "${META_DISTRO_NAME}" "META_DISTRO_NAME"
assert_equals "13" "${META_DISTRO_VERSION}" "META_DISTRO_VERSION"
assert_equals "icpc_bo" "${CONTEST_DIR}" "CONTEST_DIR"
assert_equals "contest" "${HOSTNAME}" "HOSTNAME"
assert_equals "en_US.UTF-8 es_ES.UTF-8 es_BO.UTF-8" "${SUPPORTED_LOCALES}" "SUPPORTED_LOCALES"
assert_equals "8" "${DOWNLOAD_CONNECTIONS}" "DOWNLOAD_CONNECTIONS"
assert_equals "0" "${OUTPUT_RUNTIME}" "OUTPUT_RUNTIME"
assert_equals "gnome" "${DESKTOP_PROFILE}" "DESKTOP_PROFILE default"
assert_equals "" "${ISO_PATH}" "ISO_PATH"
assert_equals "http://192.168.122.1:3142" "${APT_PROXY}" "APT_PROXY"
assert_equals "true" "${ENABLE_AUTOLOGIN}" "ENABLE_AUTOLOGIN"

DESKTOP_PROFILE=xfce4
source "${PROJECT_DIR}/config/iso.conf"
assert_equals "xfce4" "${DESKTOP_PROFILE}" "DESKTOP_PROFILE override"

assert_file "scripts/setup.d/gnome/05-desktop-defaults.sh"
assert_file "scripts/setup.d/common/05-low-ram.sh"
assert_file "scripts/setup.d/common/08-contest-security-config.sh"
assert_file "scripts/setup.d/common/12-install-vscode.sh"
assert_file "scripts/setup.d/common/23-update-config.sh"
assert_file "scripts/setup.d/common/24-graphical-target.sh"
assert_file "scripts/setup.d/common/80-apt-policy.sh"
assert_file "scripts/setup.d/common/89-prune-locales.sh"
assert_file "scripts/setup.d/common/90-initramfs.sh"
assert_file "overlay/etc/initramfs-tools/hooks/contest-overlay-tools"
assert_file "overlay/etc/systemd/system/contest-overlay-provision.service"
assert_file "overlay/etc/systemd/system/contest-update.service"
assert_file "overlay/usr/lib/contest/lib/base.sh"
assert_file "overlay/usr/lib/contest/lib/fs.sh"
assert_file "overlay/usr/lib/contest/lib/runtime-layout.sh"
assert_file "overlay/usr/lib/contest/provision-overlay.sh"
assert_file "overlay/usr/lib/contest/update.sh"
assert_file "overlay/usr/lib/contest/rollback.sh"
assert_file "scripts/run-hook-dir.sh"
assert_file "scripts/cached-curl.sh"
assert_file "scripts/build/lib/common.sh"
assert_file "scripts/build/lib/grub.sh"
assert_file "scripts/build/grub.sh"
assert_file "scripts/build/install-packages-chroot.sh"
assert_file "scripts/build/install-and-customize-chroot.sh"
assert_file "scripts/build/trim-chroot.sh"
assert_file "config/iso.local.conf.example"
assert_file "docker/apt-cacher-ng/20-ipv4.conf"

assert_file "scripts/setup.d/gnome/packages.list"
assert_file "scripts/setup.d/gnome/packages-remove.list"
assert_file "scripts/setup.d/gnome/03-default-user.sh"
assert_file "scripts/setup.d/gnome/05-desktop-defaults.sh"
assert_file "scripts/setup.d/gnome/12-gnome-extensions.sh"
assert_file "scripts/setup.d/gnome/14-gnome-defaults.sh"
assert_file "scripts/setup.d/gnome/15-user-env.sh"
assert_executable "scripts/setup.d/gnome/03-default-user.sh"
assert_executable "scripts/setup.d/gnome/05-desktop-defaults.sh"
assert_executable "scripts/setup.d/gnome/12-gnome-extensions.sh"
assert_executable "scripts/setup.d/gnome/14-gnome-defaults.sh"
assert_executable "scripts/setup.d/gnome/15-user-env.sh"
grep -qxF "gnome-shell" "${PROJECT_DIR}/scripts/setup.d/gnome/packages.list" || \
    fail "gnome sin gnome-shell"
grep -qxF "ConnectProto: v4" "${PROJECT_DIR}/docker/apt-cacher-ng/20-ipv4.conf" || \
    fail "apt-cacher debe forzar IPv4 cuando IPv6 no tiene ruta"
grep -qxF "zenity" "${PROJECT_DIR}/scripts/setup.d/gnome/packages.list" || \
    fail "gnome sin zenity para login"
grep -q 'VSCODE_PYTHON_VERSION="2024.22.1"' \
    "${PROJECT_DIR}/scripts/setup.d/common/13-install-vscode-extensions.sh" || \
    fail "VSIX de Python debe usar una versión publicada en Open VSX"
grep -q 'VSCODE_JAVA_BUILD="923"' \
    "${PROJECT_DIR}/scripts/setup.d/common/13-install-vscode-extensions.sh" || \
    fail "VSIX de Java debe usar un build publicado"
if grep -q 'kotlin-lsp' "${PROJECT_DIR}/scripts/setup.d/common/13-install-vscode-extensions.sh"; then
    fail "no descargar Kotlin LSP: sus releases no publican un VSIX"
fi
assert_file "scripts/setup.d/xfce4/packages.list"
assert_file "scripts/setup.d/xfce4/packages-remove.list"
assert_file "scripts/setup.d/xfce4/03-default-user.sh"
assert_file "scripts/setup.d/xfce4/05-desktop-defaults.sh"
assert_file "scripts/setup.d/xfce4/15-user-env.sh"
assert_executable "scripts/setup.d/xfce4/03-default-user.sh"
assert_executable "scripts/setup.d/xfce4/05-desktop-defaults.sh"
assert_executable "scripts/setup.d/xfce4/15-user-env.sh"
assert_executable "scripts/setup.d/common/05-low-ram.sh"
assert_executable "scripts/setup.d/common/08-contest-security-config.sh"
grep -qxF "lightdm" "${PROJECT_DIR}/scripts/setup.d/xfce4/packages.list" || \
    fail "xfce4 sin lightdm"
grep -qxF "xfce4-session" "${PROJECT_DIR}/scripts/setup.d/xfce4/packages.list" || \
    fail "xfce4 sin xfce4-session"
grep -qxF "zenity" "${PROJECT_DIR}/scripts/setup.d/xfce4/packages.list" || \
    fail "xfce4 sin zenity para login"
grep -qxF "libglib2.0-bin" "${PROJECT_DIR}/scripts/setup.d/xfce4/packages.list" || \
    fail "xfce4 sin libglib2.0-bin para gio"
grep -qxF "dbus-user-session" "${PROJECT_DIR}/scripts/setup.d/xfce4/packages.list" || \
    fail "xfce4 sin dbus-user-session para metadata gio"
grep -qxF "librsvg2-common" "${PROJECT_DIR}/scripts/setup.d/xfce4/packages.list" || \
    fail "xfce4 sin librsvg2-common para wallpaper SVG"
grep -q 'workspace0/last-image' "${PROJECT_DIR}/assets/contestants/bin/contestants-login-xfce.sh" || \
    fail "login XFCE debe cambiar el wallpaper activo del workspace"
grep -q 'image-path.*WALLPAPER' "${PROJECT_DIR}/scripts/setup.d/xfce4/15-user-env.sh" || \
    fail "xfce debe configurar el wallpaper inicial con image-path"
assert_executable "assets/contestants/bin/gnome-autostart.sh"
assert_executable "assets/contestants/bin/xfce-autostart.sh"
assert_executable "assets/contestants/bin/contestants-login-gnome.sh"
assert_executable "assets/contestants/bin/contestants-login-xfce.sh"
if [[ -e "${PROJECT_DIR}/assets/contestants/bin/contestants-login.sh" ]]; then
    fail "no mantener wrapper genérico contestants-login.sh; usar login específico GNOME/XFCE"
fi
assert_file "assets/contestants/misc/desktop-home.desktop"
assert_file "assets/contestants/misc/desktop-gnome-autostart.desktop"
assert_file "assets/contestants/misc/desktop-xfce-autostart.desktop"
assert_file "desktop-wallpaper.svg"
if find "${PROJECT_DIR}/assets" -iname '*icpcbo*' -o -iname '*icpc-bo*' | grep -q .; then
    fail "assets no debe tener nombres de archivos/carpetas con icpcbo/icpc-bo"
fi
grep -q 'contestants-login-gnome.sh' "${PROJECT_DIR}/assets/contestants/bin/gnome-autostart.sh" || \
    fail "gnome autostart debe ejecutar el login GNOME"
grep -q 'contestants-login-xfce.sh' "${PROJECT_DIR}/assets/contestants/bin/xfce-autostart.sh" || \
    fail "xfce autostart debe ejecutar el login XFCE"
grep -q '^OnlyShowIn=.*GNOME' "${PROJECT_DIR}/assets/contestants/misc/desktop-gnome-autostart.desktop" || \
    fail "el autostart GNOME debe limitarse a GNOME"
grep -q '^OnlyShowIn=.*XFCE' "${PROJECT_DIR}/assets/contestants/misc/desktop-xfce-autostart.desktop" || \
    fail "el autostart XFCE debe limitarse a XFCE"
grep -q 'desktop-gnome-autostart.desktop' "${PROJECT_DIR}/scripts/setup.d/gnome/15-user-env.sh" || \
    fail "gnome debe instalar su autostart específico"
grep -q 'desktop-xfce-autostart.desktop' "${PROJECT_DIR}/scripts/setup.d/xfce4/15-user-env.sh" || \
    fail "xfce debe instalar su autostart específico"
grep -q "color-scheme='prefer-dark'" "${PROJECT_DIR}/scripts/setup.d/gnome/14-gnome-defaults.sh" || \
    fail "gnome debe iniciar en modo oscuro"
grep -q 'ThemeName.*Adwaita-dark' "${PROJECT_DIR}/scripts/setup.d/xfce4/15-user-env.sh" || \
    fail "xfce debe iniciar con tema oscuro en el usuario"
grep -q 'ThemeName.*Adwaita-dark' "${PROJECT_DIR}/scripts/setup.d/xfce4/05-desktop-defaults.sh" || \
    fail "xfce debe tener tema oscuro por defecto del sistema"
if grep -qxF "gnome-shell" "${PROJECT_DIR}/scripts/setup.d/xfce4/packages.list"; then
    fail "xfce4 no debe incluir gnome-shell"
fi

grep -q 'Inicio.html' "${PROJECT_DIR}/scripts/setup.d/xfce4/15-user-env.sh" || \
    fail "xfce4 debe usar un link HTML natural en el escritorio"
grep -q 'metadata::xfce-exe-checksum' "${PROJECT_DIR}/scripts/setup.d/xfce4/15-user-env.sh" || \
    fail "xfce4 debe marcar como confiables los accesos directos del escritorio"

if grep -RInE 'icpcboconf|/sbin/contest\.sh' \
    "${PROJECT_DIR}/scripts/setup.d/gnome/15-user-env.sh" \
    "${PROJECT_DIR}/scripts/setup.d/xfce4/15-user-env.sh" >/dev/null; then
    fail "no referenciar comandos administrativos inexistentes en perfiles de usuario"
fi

assert_executable "overlay/etc/initramfs-tools/hooks/contest-overlay-tools"
assert_executable "overlay/usr/lib/contest/provision-overlay.sh"
assert_executable "overlay/usr/lib/contest/update.sh"
assert_executable "overlay/usr/lib/contest/contract.py"
assert_executable "overlay/usr/lib/contest/rollback.sh"
assert_executable "overlay/usr/lib/contest/lib/base.sh"
assert_executable "overlay/usr/lib/contest/lib/fs.sh"
assert_executable "overlay/usr/lib/contest/lib/runtime-layout.sh"
assert_executable "scripts/setup.d/common/12-install-vscode.sh"
assert_executable "scripts/setup.d/common/23-update-config.sh"
assert_executable "scripts/setup.d/common/24-graphical-target.sh"
assert_executable "scripts/setup.d/common/89-prune-locales.sh"
assert_executable "scripts/run-hook-dir.sh"
assert_executable "scripts/cached-curl.sh"
assert_executable "scripts/build/lib/common.sh"
assert_executable "scripts/build/lib/grub.sh"
assert_executable "scripts/build/grub.sh"
assert_executable "scripts/build/install-packages-chroot.sh"
assert_executable "scripts/build/install-and-customize-chroot.sh"
assert_executable "scripts/build/trim-chroot.sh"

if [[ -d "${PROJECT_DIR}/config/meta" ]]; then
    fail "config/meta should not exist anymore"
fi

if find "${PROJECT_DIR}/scripts/setup.d" -maxdepth 1 -type f -name '*.sh' | grep -q .; then
    fail "hooks sueltos en scripts/setup.d"
fi

for profile in gnome xfce4; do
    while IFS= read -r common_hook; do
        hook_name="$(basename "${common_hook}")"
        if [[ -f "${PROJECT_DIR}/scripts/setup.d/${profile}/${hook_name}" ]]; then
            fail "duplicate setup hook in common and ${profile}: ${hook_name}"
        fi
    done < <(find "${PROJECT_DIR}/scripts/setup.d/common" -maxdepth 1 -type f -name '*.sh' | sort)
done

if [[ -e "${PROJECT_DIR}/config/packages.list" || -e "${PROJECT_DIR}/config/packages-remove.list" ]]; then
    fail "listas de paquetes fuera de scripts/setup.d"
fi

required_security_variables=(
    GRUB_ADMIN_PASSWORD_HASH UPDATE_SIGNATURE_PUBKEY UPDATE_SIGNATURE_PUBKEY_FILE
    UPDATE_SIGNING_PRIVATE_KEY_FILE
    TEAM_ID_REQUIRED
)
for variable in "${required_security_variables[@]}"; do
    declare -p "${variable}" >/dev/null 2>&1 || fail "missing security variable: ${variable}"
done

assert_equals "icpc" "${DEFAULT_PASSWORD}" "DEFAULT_PASSWORD (credencial de escritorio conocida)"
assert_equals "" "${UPDATE_MANIFEST_URL}" "UPDATE_MANIFEST_URL safe default"
assert_equals "false" "${UPDATE_CHECK_ON_BOOT}" "UPDATE_CHECK_ON_BOOT safe default"
assert_equals "true" "${TEAM_ID_REQUIRED}" "TEAM_ID_REQUIRED default"
[[ "${UPDATE_SIGNATURE_PUBKEY}" == /* ]] || \
    fail "UPDATE_SIGNATURE_PUBKEY must be an absolute public-key path"

grep -q 'INSTALL_OWNER:-root' \
    "${PROJECT_DIR}/scripts/setup.d/common/08-contest-security-config.sh" || \
    fail "security hook must default to root ownership"
for hook in "${PROJECT_DIR}/scripts/setup.d/common/23-update-config.sh"; do
    grep -q 'install -d -o root -g root -m 0755 /etc/contestiso' "${hook}" || \
        fail "config hook must install /etc/contestiso as root:root 0755: ${hook}"
done
grep -q 'chmod 0644' "${PROJECT_DIR}/scripts/setup.d/common/08-contest-security-config.sh" || \
    fail "security hook must make public configuration mode 0644"
if grep -q 'GRUB_ADMIN_PASSWORD_HASH' \
    "${PROJECT_DIR}/scripts/setup.d/common/08-contest-security-config.sh"; then
    fail "GRUB password hash must not be persisted in public runtime configuration"
fi

low_ram_hook="${PROJECT_DIR}/scripts/setup.d/common/05-low-ram.sh"
grep -q 'systemd-zram-generator' "${low_ram_hook}" || \
    fail "low-ram hook must provision zram swap"
grep -q 'earlyoom' "${low_ram_hook}" || \
    fail "low-ram hook must provision earlyoom against memory freezes"
grep -q 'compression-algorithm = zstd' "${low_ram_hook}" || \
    fail "low-ram hook must compress zram with zstd"

graphical_hook="${PROJECT_DIR}/scripts/setup.d/common/24-graphical-target.sh"
grep -q 'systemctl set-default graphical.target' "${graphical_hook}" || \
    fail "sin set-default graphical.target el equipo arranca en login de texto"

for schema in "${PROJECT_DIR}"/config/contracts/*.schema.json; do
    python3 -m json.tool "${schema}" >/dev/null || fail "invalid JSON contract: ${schema}"
    grep -q '"additionalProperties": false' "${schema}" || \
        fail "contract must reject unknown fields: ${schema}"
    grep -q '"x-maxBytes": 8192' "${schema}" || \
        fail "contract must declare the 8 KiB byte limit: ${schema}"
done

security_root="${tmp_dir}/security-root"
env \
    INSTALL_ROOT="${security_root}" \
    INSTALL_OWNER="$(id -un)" \
    INSTALL_GROUP="$(id -gn)" \
    UPDATE_CHECK_ON_BOOT=false \
    UPDATE_MANIFEST_URL= \
    UPDATE_SIGNATURE_PUBKEY=/usr/share/contest/keys/update-signing.pub \
    UPDATE_SIGNATURE_PUBKEY_SOURCE="${tmp_dir}/missing-public-key" \
    TEAM_ID_REQUIRED=true \
    bash "${PROJECT_DIR}/scripts/setup.d/common/08-contest-security-config.sh"

assert_equals "755" "$(stat -c %a "${security_root}/etc/contestiso")" \
    "/etc/contestiso mode"
assert_equals "700" "$(stat -c %a "${security_root}/etc/contestiso/secrets")" \
    "secret directory mode"

tracked_security_paths=(
    "${PROJECT_DIR}/config"
    "${PROJECT_DIR}/scripts"
    "${PROJECT_DIR}/overlay"
    "${PROJECT_DIR}/remote"
)
if grep -RIl -- 'BEGIN .*PRIVATE KEY' "${tracked_security_paths[@]}" | grep -q .; then
    fail "private key material found in tracked runtime/build files"
fi
if grep -REn '^[[:space:]]*(GRUB_ADMIN_PASSWORD_HASH|UPDATE_SIGNING_PRIVATE_KEY_FILE)=[\"'\"'][^\"'\"'$]+[\"'\"']' \
    "${PROJECT_DIR}/config/iso.conf" >/dev/null; then
    fail "secret-bearing defaults (GRUB hash, clave de firma) deben quedar vacíos en config/iso.conf"
fi
if find "${PROJECT_DIR}/config" "${PROJECT_DIR}/scripts" "${PROJECT_DIR}/overlay" \
    "${PROJECT_DIR}/remote" \
    -type f \( -name '*.key' -o -name '*.pem' -o -name 'id_rsa' -o -name 'id_ed25519' \) \
    -print -quit | grep -q .; then
    fail "private-key-shaped file found in tracked runtime/build paths"
fi
grep -qxF "config/iso.local.conf" "${PROJECT_DIR}/.gitignore" || \
    fail "local secret/config override must be ignored by Git"

assert_package "network-manager"
assert_package "wpasupplicant"
assert_package "wireless-regdb"
assert_package "iw"
assert_package "rfkill"
assert_package "firmware-iwlwifi"
assert_package "firmware-realtek"
assert_package "firmware-atheros"
assert_package "firmware-ath9k-htc"
assert_package "firmware-brcm80211"
assert_package "firmware-mediatek"
assert_package "firmware-misc-nonfree"
assert_package "e2fsprogs"

grep -q 'copy_required_binary truncate' "${PROJECT_DIR}/overlay/etc/initramfs-tools/hooks/contest-overlay-tools" || \
    fail "initramfs hook must bundle truncate for first-boot overlay creation"
grep -q 'copy_contest_binary mke2fs /usr/lib/contest-initramfs/bin/mke2fs.real' "${PROJECT_DIR}/overlay/etc/initramfs-tools/hooks/contest-overlay-tools" || \
    fail "initramfs hook must bundle mke2fs for first-boot overlay creation"

search_paths=()
for path in \
    "${PROJECT_DIR}/config" \
    "${PROJECT_DIR}/overlay" \
    "${PROJECT_DIR}/scripts" \
    "${PROJECT_DIR}/start.sh" \
    "${PROJECT_DIR}/README.md" \
    "${PROJECT_DIR}/Dockerfile" \
    "${PROJECT_DIR}/docker/apt-cacher-ng/Dockerfile"; do
    [[ -e "${path}" ]] && search_paths+=("${path}")
done

if command -v rg >/dev/null 2>&1; then
    if rg -n -i "nutella" "${search_paths[@]}" >/dev/null; then
        fail "old 'nutella' references still exist in runtime/build files"
    fi
else
    if grep -Rni -- "nutella" "${search_paths[@]}" >/dev/null 2>&1; then
        fail "old 'nutella' references still exist in runtime/build files"
    fi
fi

echo "PASS: config defaults, branding, Debian 13, and Wi-Fi packages look correct."
