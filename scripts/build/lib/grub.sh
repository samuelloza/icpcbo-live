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
    printf ' contest_dir=%s contest_root=%s contest_persist=%s console=tty0 console=ttyS0,115200n8' \
        "$(grub_runtime_dir)" \
        "${ROOT_SQUASH_NAME}" \
        "${persist_mode}"
    printf ' contest.boot_source=%s' "${boot_source}"
    printf ' contest_min_ram_mb=%s' "${MIN_RAM_MB}"

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
    shift 5

    {
        printf '    menuentry "%s" {\n' "${title}"

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
    shift 5

    {
        printf '    menuentry "%s" {\n' "${title}"
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

    {
        printf 'menuentry "%s (folder mode)" {\n' "${ISO_NAME}"
        printf '    '
        grub_linux_line "auto" "splash" "hdd"
        printf '    initrd %s\n' "$(grub_initrd_path)"
        echo '}'
    } > "${file}"
}

write_iso_grub_cfg() {
    local file="$1"

    cat > "${file}" <<EOF
set default=0
set timeout=30
set timeout_style=menu

# Consola serial (para virsh console / captura de logs).
serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
terminal_input  serial console
terminal_output serial console

# Busca sistema instalado en disco (overlay o completo).
search --no-floppy --set=full_hdd_root --file $(grub_runtime_dir)/.contest-full-installed || true
search --no-floppy --set=hdd_root --file $(grub_runtime_dir)/.contest-installed || true

if [ -n "\${full_hdd_root}" ]; then

# ── Instalacion completa detectada en disco ───────────────────────────────
set default=0
set timeout=15
    menuentry "Sistema instalado. Retire el USB y reinicie." {
        echo ""
        echo "  El sistema ICPC Bolivia ya esta instalado en el disco."
        echo "  Retire el USB y reinicie para arrancar desde el disco."
        echo ""
        echo "  Reiniciando en 10 segundos..."
        sleep 10
        reboot
    }

elif [ -n "\${hdd_root}" ]; then

# ── Arranque persistente desde disco ──────────────────────────────────────
EOF

    append_grub_hdd_menuentry \
        "${file}" \
        "Iniciar ICPC Bolivia" \
        "hdd_root" "on" "splash"

    append_grub_menuentry \
        "${file}" \
        "Reinstalar ICPC Bolivia" \
        "iso" "off" "plain" \
        "contest.reinstall=1"

    cat >> "${file}" <<'EOF'
else

# ── Instalacion ───────────────────────────────────────────────────────────
EOF

    append_grub_menuentry \
        "${file}" \
        "ICPC BO" \
        "iso" "off" "plain"

    cat >> "${file}" <<'EOF'
fi
EOF
}
