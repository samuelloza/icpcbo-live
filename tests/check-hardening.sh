#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GNOME_USER_HOOK="${PROJECT_DIR}/scripts/setup.d/gnome/03-default-user.sh"
XFCE_USER_HOOK="${PROJECT_DIR}/scripts/setup.d/xfce4/03-default-user.sh"
SSH_HARDENING="${PROJECT_DIR}/overlay/etc/ssh/sshd_config.d/90-contest-hardening.conf"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_line() {
    local expected="$1"
    local file="$2"

    grep -Fqx -- "${expected}" "${file}" || fail "${file} must contain: ${expected}"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

stub_bin="${tmp_dir}/bin"
mkdir -p "${stub_bin}"

cat > "${stub_bin}/id" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "${stub_bin}/getent" <<'EOF'
#!/usr/bin/env bash
case "${2:-}" in
    audio|video|netdev|plugdev|sudo|adm|admin|wheel) exit 0 ;;
    *) exit 2 ;;
esac
EOF

cat > "${stub_bin}/usermod" <<'EOF'
#!/usr/bin/env bash
printf 'usermod'
printf ' %q' "$@"
printf '\n'
EOF

cat > "${stub_bin}/passwd" <<'EOF'
#!/usr/bin/env bash
printf 'passwd'
printf ' %q' "$@"
printf '\n'
EOF

cat > "${stub_bin}/chpasswd" <<'EOF'
#!/usr/bin/env bash
echo "chpasswd must not be called with an empty password" >&2
exit 1
EOF

chmod +x "${stub_bin}"/*

run_user_hook() {
    local hook="$1"
    PATH="${stub_bin}:${PATH}" \
        DEFAULT_USER=icpc \
        DEFAULT_PASSWORD= \
        ENABLE_AUTOLOGIN=false \
        bash "${hook}"
}

gnome_calls="$(run_user_hook "${GNOME_USER_HOOK}")"
[[ "${gnome_calls}" == "usermod -G audio\\,video icpc" ]] \
    || fail "GNOME must set only audio and video supplementary groups"

xfce_calls="$(run_user_hook "${XFCE_USER_HOOK}")"
[[ "${xfce_calls}" == "usermod -G audio\\,video\\,netdev\\,plugdev icpc" ]] \
    || fail "XFCE must set only desktop device supplementary groups"

if grep -Eq '(^|[[:space:],])(sudo|adm|admin|wheel)([[:space:],]|$)' \
    "${GNOME_USER_HOOK}" "${XFCE_USER_HOOK}"; then
    fail "default user hooks must not grant administrative groups"
fi

# Autologin GNOME + XFCE con ENABLE_AUTOLOGIN=true (sin contraseña).
autologin_etc="${tmp_dir}/autologin-etc"
PATH="${stub_bin}:${PATH}" DEFAULT_USER=icpc DEFAULT_PASSWORD= \
    ENABLE_AUTOLOGIN=true ETC_DIR="${autologin_etc}/gnome" \
    bash "${GNOME_USER_HOOK}" >/dev/null
gdm_conf="${autologin_etc}/gnome/gdm3/custom.conf"
[[ -f "${gdm_conf}" ]] || fail "GNOME autologin: falta ${gdm_conf#${autologin_etc}/gnome}"
assert_line "AutomaticLoginEnable=true" "${gdm_conf}"
assert_line "AutomaticLogin=icpc" "${gdm_conf}"

PATH="${stub_bin}:${PATH}" DEFAULT_USER=icpc DEFAULT_PASSWORD= \
    ENABLE_AUTOLOGIN=true ETC_DIR="${autologin_etc}/xfce" \
    bash "${XFCE_USER_HOOK}" >/dev/null
lightdm_conf="${autologin_etc}/xfce/lightdm/lightdm.conf.d/50-icpc-autologin.conf"
[[ -f "${lightdm_conf}" ]] || fail "XFCE autologin: falta 50-icpc-autologin.conf"
assert_line "autologin-user=icpc" "${lightdm_conf}"
assert_line "autologin-user-timeout=0" "${lightdm_conf}"
assert_line "user-session=xfce" "${lightdm_conf}"

# ENABLE_AUTOLOGIN=false no escribe configuración de autologin.
PATH="${stub_bin}:${PATH}" DEFAULT_USER=icpc DEFAULT_PASSWORD= \
    ENABLE_AUTOLOGIN=false ETC_DIR="${autologin_etc}/off" \
    bash "${GNOME_USER_HOOK}" >/dev/null
[[ ! -e "${autologin_etc}/off/gdm3/custom.conf" ]] \
    || fail "GNOME no debe escribir autologin con ENABLE_AUTOLOGIN=false"

# Con DEFAULT_PASSWORD no vacío la cuenta recibe contraseña (respaldo manual
# del staff si el autologin falla).
chpasswd_log="${tmp_dir}/chpasswd.log"
cat > "${stub_bin}/chpasswd" <<EOF
#!/usr/bin/env bash
cat >> "${chpasswd_log}"
EOF
chmod +x "${stub_bin}/chpasswd"
PATH="${stub_bin}:${PATH}" DEFAULT_USER=icpc DEFAULT_PASSWORD=icpc \
    ENABLE_AUTOLOGIN=true ETC_DIR="${autologin_etc}/pw" \
    bash "${GNOME_USER_HOOK}" >/dev/null
grep -qx 'icpc:icpc' "${chpasswd_log}" \
    || fail "con DEFAULT_PASSWORD debe fijarse la contraseña de la cuenta"
grep -qx 'root:icpc' "${chpasswd_log}" \
    || fail "con DEFAULT_PASSWORD debe permitir su - como root"

assert_line "PermitRootLogin no" "${SSH_HARDENING}"
assert_line "PasswordAuthentication no" "${SSH_HARDENING}"
assert_line "KbdInteractiveAuthentication no" "${SSH_HARDENING}"

# shellcheck source=/dev/null
source "${PROJECT_DIR}/config/iso.conf"
# shellcheck source=/dev/null
source "${PROJECT_DIR}/scripts/build/grub.sh"

runtime_grub="${tmp_dir}/runtime-grub.cfg"
iso_grub="${tmp_dir}/iso-grub.cfg"
GRUB_ADMIN_PASSWORD_HASH="grub.pbkdf2.sha512.10000.ABCD0123.DEADBEEF"

write_runtime_grub_entry "${runtime_grub}"
write_iso_grub_cfg "${iso_grub}"

for grub_cfg in "${runtime_grub}" "${iso_grub}"; do
    assert_line 'set superusers="contestadmin"' "${grub_cfg}"
    assert_line \
        "password_pbkdf2 contestadmin ${GRUB_ADMIN_PASSWORD_HASH}" \
        "${grub_cfg}"
done

grep -Fq 'menuentry "'"${ISO_NAME}"' (folder mode)" --unrestricted {' "${runtime_grub}" \
    || fail "runtime normal entry must be unrestricted"
grep -Fq 'menuentry "Iniciar ICPC BO (persistencia del home)" --unrestricted {' "${iso_grub}" \
    || fail "normal ISO entries must be unrestricted"

if grep -E 'menuentry "(Limpiar home|Borrar archivos de instalacion)" --unrestricted' \
    "${iso_grub}"; then
    fail "destructive GRUB entries must require the configured superuser"
fi

GRUB_ADMIN_PASSWORD_HASH=""
printf 'stale unprotected config\n' > "${tmp_dir}/must-not-exist.cfg"
if write_iso_grub_cfg "${tmp_dir}/must-not-exist.cfg" 2> "${tmp_dir}/empty-hash.err"; then
    fail "empty GRUB admin hash must fail closed"
fi
[[ ! -e "${tmp_dir}/must-not-exist.cfg" ]] \
    || fail "GRUB config must not be created without an admin hash"

GRUB_ADMIN_PASSWORD_HASH="not-a-pbkdf2-hash"
if write_runtime_grub_entry "${tmp_dir}/invalid-runtime.cfg" 2> "${tmp_dir}/invalid-hash.err"; then
    fail "invalid GRUB admin hash must fail closed"
fi
[[ ! -e "${tmp_dir}/invalid-runtime.cfg" ]] \
    || fail "runtime GRUB config must not be created with an invalid hash"

echo "PASS: local users, root console access, SSH restrictions and GRUB actions are configured."
