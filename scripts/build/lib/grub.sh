#!/usr/bin/env bash

set -euo pipefail

grub_runtime_dir() {
    printf '/%s\n' "${CONTEST_DIR}"
}

grub_kernel_path() {
    printf '%s/vmlinuz\n' "$(grub_runtime_dir)"
}

grub_initrd_path() {
    printf '%s/initrd.img\n' "$(grub_runtime_dir)"
}

require_grub_admin_password_hash() {
    if [[ ! "${GRUB_ADMIN_PASSWORD_HASH:-}" =~ ^grub\.pbkdf2\.sha512\.[0-9]+\.[[:xdigit:]]+\.[[:xdigit:]]+$ ]]; then
        echo "FATAL: GRUB_ADMIN_PASSWORD_HASH must contain a GRUB PBKDF2-SHA512 hash" >&2
        return 1
    fi
}

write_grub_auth() {
    cat <<EOF
set superusers="contestadmin"
password_pbkdf2 contestadmin ${GRUB_ADMIN_PASSWORD_HASH}
EOF
}

write_grub_terminal() {
    cat <<'EOF'
if loadfont unicode ; then
    insmod gfxterm
    set gfxmode=auto
    terminal_output gfxterm
fi
EOF
}

grub_linux_line() {
    local persist_mode="$1"
    local splash_mode="$2"
    local boot_source="$3"
    shift 3

    local extra_args=("$@")

    printf 'linux %s' "$(grub_kernel_path)"
    if [[ "${splash_mode}" == "splash" ]]; then
        printf ' quiet splash'
    fi
    printf ' contest_dir=%s contest_root=%s contest_persist=%s console=tty0' \
        "$(grub_runtime_dir)" \
        "${ROOT_SQUASH_NAME}" \
        "${persist_mode}"
    printf ' contest.boot_source=%s' "${boot_source}"
    if [[ -n "${MIN_RAM_MB}" ]]; then
        printf ' contest_min_ram_mb=%s' "${MIN_RAM_MB}"
    fi

    local arg
    for arg in "${extra_args[@]}"; do
        printf ' %s' "${arg}"
    done

    printf '\n'
}

append_grub_menuentry() {
    local file="$1"
    local title="$2"
    local root_mode="$3"
    local persist_mode="$4"
    local splash_mode="$5"
    local access_mode="$6"
    shift 6

    {
        printf '    menuentry "%s"%s {\n' "${title}" "${access_mode}"

        if [[ "${root_mode}" == "hdd" ]]; then
            echo '        set root=(${hdd_root})'
        fi

        printf '        '
        grub_linux_line "${persist_mode}" "${splash_mode}" "${root_mode}" "$@"
        printf '        initrd %s\n' "$(grub_initrd_path)"
        echo '    }'
        echo
    } >> "${file}"
}

append_grub_hdd_menuentry() {
    local file="$1"
    local title="$2"
    local root_var="$3"
    local persist_mode="$4"
    local splash_mode="$5"
    local access_mode="$6"
    shift 6

    {
        printf '    menuentry "%s"%s {\n' "${title}" "${access_mode}"
        printf '        set root=(${%s})\n' "${root_var}"
        printf '        '
        grub_linux_line "${persist_mode}" "${splash_mode}" "hdd" "$@"
        printf '        initrd %s\n' "$(grub_initrd_path)"
        echo '    }'
        echo
    } >> "${file}"
}

write_runtime_grub_entry() {
    local file="$1"

    if ! require_grub_admin_password_hash; then
        rm -f -- "${file}"
        return 1
    fi

    {
        write_grub_auth
        echo
        printf 'menuentry "%s (folder mode)" --unrestricted {\n' "${ISO_NAME}"
        printf '    '
        grub_linux_line "auto" "splash" "hdd" "contest.persist_scope=home"
        printf '    initrd %s\n' "$(grub_initrd_path)"
        echo '}'
    } > "${file}"
}

write_iso_grub_cfg() {
    local file="$1"

    if ! require_grub_admin_password_hash; then
        rm -f -- "${file}"
        return 1
    fi

    cat > "${file}" <<EOF
set default=0
set timeout=30
set timeout_style=menu

$(write_grub_auth)

$(write_grub_terminal)

# Busca sistema instalado en disco.
if search --no-floppy --quiet --set=hdd_root --file $(grub_runtime_dir)/.contest-installed; then
    true
fi

if [ -n "\${hdd_root}" ]; then

# ── Arranque persistente desde disco ──────────────────────────────────────
EOF

    append_grub_hdd_menuentry \
        "${file}" \
        "Iniciar ICPC BO (persistencia del home)" \
        "hdd_root" "on" "splash" " --unrestricted" \
        "contest.persist_scope=home"

    append_grub_hdd_menuentry \
        "${file}" \
        "Limpiar home" \
        "hdd_root" "on" "plain" "" \
        "contest.persist_scope=home" \
        "contest.reset_home=1"

    append_grub_hdd_menuentry \
        "${file}" \
        "Borrar archivos de instalacion" \
        "hdd_root" "on" "plain" "" \
        "contest.clean_install=1"

    append_grub_menuentry \
        "${file}" \
        "Probar live (sin persistencia)" \
        "iso" "off" "plain" " --unrestricted" \
        "contest.install_mode=live"

    cat >> "${file}" <<'EOF'
else

# ── Instalacion ───────────────────────────────────────────────────────────
EOF

    append_grub_menuentry \
        "${file}" \
        "Iniciar ICPC BO (persistencia del home)" \
        "iso" "on" "splash" " --unrestricted" \
        "contest.persist_scope=home"

    append_grub_menuentry \
        "${file}" \
        "Limpiar home" \
        "iso" "on" "plain" "" \
        "contest.persist_scope=home" \
        "contest.reset_home=1"

    append_grub_menuentry \
        "${file}" \
        "Borrar archivos de instalacion" \
        "iso" "on" "plain" "" \
        "contest.clean_install=1"

    append_grub_menuentry \
        "${file}" \
        "Probar live (sin persistencia)" \
        "iso" "off" "plain" " --unrestricted" \
        "contest.install_mode=live"

    cat >> "${file}" <<'EOF'
fi
EOF
}
