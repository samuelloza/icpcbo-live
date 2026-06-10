#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "${PROJECT_DIR}/config/iso.conf"
# shellcheck source=/dev/null
source "${PROJECT_DIR}/scripts/build/grub.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_file_equals() {
    local expected="$1"
    local actual_file="$2"
    local label="$3"

    local actual
    actual="$(cat "${actual_file}")"

    if [[ "${actual}" != "${expected}" ]]; then
        printf 'Expected %s:\n%s\n' "${label}" "${expected}" >&2
        printf 'Actual %s:\n%s\n' "${label}" "${actual}" >&2
        fail "${label} does not match expected content"
    fi
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

runtime_grub="${tmp_dir}/grub-entry.cfg"
iso_grub="${tmp_dir}/grub.cfg"

write_runtime_grub_entry "${runtime_grub}"
write_iso_grub_cfg "${iso_grub}"

grub_hdd_ref='${hdd_root}'

expected_runtime_grub="$(cat <<EOF_RUNTIME
menuentry "${ISO_NAME} (folder mode)" {
    linux /${CONTEST_DIR}/vmlinuz quiet splash contest_dir=/${CONTEST_DIR} contest_root=${ROOT_SQUASH_NAME} contest_persist=auto console=tty0 console=ttyS0,115200n8 contest.boot_source=hdd contest.persist_scope=home
    initrd /${CONTEST_DIR}/initrd.img
}
EOF_RUNTIME
)"

expected_iso_grub="$(cat <<EOF_ISO
set default=0
set timeout=30
set timeout_style=menu

# Consola serial (para virsh console / captura de logs).
serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
terminal_input  serial console
terminal_output serial console

# Busca sistema instalado en disco (overlay o completo).
search --no-floppy --set=full_hdd_root --file /${CONTEST_DIR}/.contest-full-installed || true
search --no-floppy --set=hdd_root --file /${CONTEST_DIR}/.contest-installed || true

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
    menuentry "Iniciar ICPC BO (persistencia del home)" {
        set root=(${grub_hdd_ref})
        linux /${CONTEST_DIR}/vmlinuz quiet splash contest_dir=/${CONTEST_DIR} contest_root=${ROOT_SQUASH_NAME} contest_persist=on console=tty0 console=ttyS0,115200n8 contest.boot_source=hdd contest.persist_scope=home
        initrd /${CONTEST_DIR}/initrd.img
    }

    menuentry "Limpiar home" {
        set root=(${grub_hdd_ref})
        linux /${CONTEST_DIR}/vmlinuz contest_dir=/${CONTEST_DIR} contest_root=${ROOT_SQUASH_NAME} contest_persist=on console=tty0 console=ttyS0,115200n8 contest.boot_source=hdd contest.persist_scope=home contest.reset_home=1
        initrd /${CONTEST_DIR}/initrd.img
    }

    menuentry "Borrar archivos de instalacion" {
        set root=(${grub_hdd_ref})
        linux /${CONTEST_DIR}/vmlinuz contest_dir=/${CONTEST_DIR} contest_root=${ROOT_SQUASH_NAME} contest_persist=on console=tty0 console=ttyS0,115200n8 contest.boot_source=hdd contest.clean_install=1
        initrd /${CONTEST_DIR}/initrd.img
    }

    menuentry "Probar live (sin persistencia)" {
        linux /${CONTEST_DIR}/vmlinuz contest_dir=/${CONTEST_DIR} contest_root=${ROOT_SQUASH_NAME} contest_persist=off console=tty0 console=ttyS0,115200n8 contest.boot_source=iso contest.install_mode=live
        initrd /${CONTEST_DIR}/initrd.img
    }

else

# ── Instalacion ───────────────────────────────────────────────────────────
    menuentry "Iniciar ICPC BO (persistencia del home)" {
        linux /${CONTEST_DIR}/vmlinuz quiet splash contest_dir=/${CONTEST_DIR} contest_root=${ROOT_SQUASH_NAME} contest_persist=on console=tty0 console=ttyS0,115200n8 contest.boot_source=iso contest.persist_scope=home
        initrd /${CONTEST_DIR}/initrd.img
    }

    menuentry "Limpiar home" {
        linux /${CONTEST_DIR}/vmlinuz contest_dir=/${CONTEST_DIR} contest_root=${ROOT_SQUASH_NAME} contest_persist=on console=tty0 console=ttyS0,115200n8 contest.boot_source=iso contest.persist_scope=home contest.reset_home=1
        initrd /${CONTEST_DIR}/initrd.img
    }

    menuentry "Borrar archivos de instalacion" {
        linux /${CONTEST_DIR}/vmlinuz contest_dir=/${CONTEST_DIR} contest_root=${ROOT_SQUASH_NAME} contest_persist=on console=tty0 console=ttyS0,115200n8 contest.boot_source=iso contest.clean_install=1
        initrd /${CONTEST_DIR}/initrd.img
    }

    menuentry "Probar live (sin persistencia)" {
        linux /${CONTEST_DIR}/vmlinuz contest_dir=/${CONTEST_DIR} contest_root=${ROOT_SQUASH_NAME} contest_persist=off console=tty0 console=ttyS0,115200n8 contest.boot_source=iso contest.install_mode=live
        initrd /${CONTEST_DIR}/initrd.img
    }

fi
EOF_ISO
)"

assert_file_equals "${expected_runtime_grub}" "${runtime_grub}" "runtime grub-entry.cfg"
assert_file_equals "${expected_iso_grub}" "${iso_grub}" "ISO grub.cfg"

echo "PASS: GRUB config generation matches the expected menu entries."
