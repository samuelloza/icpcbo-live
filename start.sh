#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="${PROJECT_DIR}/scripts/build.sh"

# shellcheck source=./config/iso.conf
source "${PROJECT_DIR}/config/iso.conf"

run_as_host_user() {
    sudo -u "${SUDO_USER:-${USER}}" "$@"
}

ensure_root() {
    [[ "${EUID}" -eq 0 ]] && return 0
    echo "[start.sh] Se requiere root. Ejecutando con sudo..."
    exec sudo -E bash "${BASH_SOURCE[0]}" "$@"
}

resolve_output_dir() {
    local output_dir="${OUTPUT_DIR}"

    if [[ "${output_dir}" == /work/* ]] && { [[ ! -d /work ]] || [[ ! -w /work ]]; }; then
        output_dir="${PROJECT_TMP_DIR}/output"
    fi

    if [[ -e "${output_dir}" && ! -w "${output_dir}" ]]; then
        output_dir="${PROJECT_TMP_DIR}/output"
    elif [[ ! -e "${output_dir}" && ! -w "$(dirname "${output_dir}")" ]]; then
        output_dir="${PROJECT_TMP_DIR}/output"
    fi

    printf '%s\n' "${output_dir}"
}

latest_iso_path() {
    local output_dir="${1:?missing output dir}"
    find "${output_dir}" -maxdepth 1 -type f -name '*.iso' -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr \
        | head -n1 \
        | cut -d' ' -f2- \
        || true
}

OUTPUT_DIR_RESOLVED="$(resolve_output_dir)"
if [[ -z "${ISO_PATH}" ]]; then
    ISO_PATH="$(latest_iso_path "${OUTPUT_DIR_RESOLVED}")"
fi

create_lab_disk() {
    local disk_path="${1:-${LAB_DISK_PATH}}"
    local size_gb="${2:-12}"

    if [[ -f "${disk_path}" ]]; then
        echo "Ya existe un disco en ${disk_path}"
        read -r -p "Sobreescribir? [s/N]: " confirm
        [[ "${confirm}" =~ ^[sS]$ ]] || return 0
        rm -f "${disk_path}"
    fi

    command -v guestfish >/dev/null 2>&1 || {
        echo "ERROR: guestfish no encontrado. Instalá: sudo apt install libguestfs-tools" >&2
        return 1
    }

    echo "Creando disco NTFS vacío (${size_gb} GB): ${disk_path}"
    mkdir -p "$(dirname "${disk_path}")"
    qemu-img create -f qcow2 "${disk_path}" "${size_gb}G"

    guestfish -a "${disk_path}" <<'GUESTFISH'
run
part-init /dev/sda mbr
part-add /dev/sda p 2048 -1
mkfs ntfs /dev/sda1
GUESTFISH
}

reset_vm() {
    local name="$1"
    virsh destroy "${name}" 2>/dev/null || true
    virsh undefine "${name}" 2>/dev/null || true
}

ensure_lab_disk() {
    if [[ ! -f "${LAB_DISK_PATH}" ]]; then
        create_lab_disk "${LAB_DISK_PATH}" "${DISK_SIZE_GB}"
    else
        echo "Disco lab: ${LAB_DISK_PATH}  ($(qemu-img info "${LAB_DISK_PATH}" | grep 'virtual size' | awk '{print $3, $4}'))"
    fi
}

require_iso() {
    local selected_iso="${1-}"

    if [[ -z "${selected_iso}" || ! -f "${selected_iso}" ]]; then
        echo "ISO no encontrado. Genera uno primero en ${OUTPUT_DIR_RESOLVED}" >&2
        print_grub_preview_hint "${OUTPUT_DIR_RESOLVED}"
        return 1
    fi
}

launch_vm() {
    local selected_iso="${1:?missing ISO path}"
    local wipe_lab_disk="${2:-0}"

    if [[ "${wipe_lab_disk}" == "1" && -f "${LAB_DISK_PATH}" ]]; then
        echo "Borrando disco lab: ${LAB_DISK_PATH}"
        rm -f "${LAB_DISK_PATH}"
    fi

    ensure_lab_disk
    reset_vm "${VM_NAME}"

    echo "Iniciando VM  ISO: $(basename "${selected_iso}")  HDD: $(basename "${LAB_DISK_PATH}")"
    virt-install \
        --connect qemu:///system \
        --name "${VM_NAME}" \
        --ram 6048 \
        --vcpus 2 \
        --disk "path=${LAB_DISK_PATH},format=qcow2,bus=virtio" \
        --os-variant debian13 \
        --cdrom "${selected_iso}" \
        --network network=default \
        --graphics spice \
        --video virtio \
        --serial pty \
        --boot cdrom,hd,menu=on \
        --cpu host-model
}

launch_winxp() {
    local with_iso="${1:-0}"
    local selected_iso="${2:-}"
    local extra_args=()

    [[ -f "${WIN_XP_DISK}" ]] || {
        echo "ERROR: disco Windows XP no encontrado: ${WIN_XP_DISK}" >&2
        return 1
    }

    chmod o+x "$(dirname "${WIN_XP_DISK}")" 2>/dev/null || true
    reset_vm "${WIN_XP_VM_NAME}"
    ensure_lab_disk

    if [[ "${with_iso}" == "1" ]]; then
        require_iso "${selected_iso}"
        echo "ISO contest: ${selected_iso}"
        extra_args=(--cdrom "${selected_iso}" --boot cdrom,hd,menu=on)
    else
        extra_args=(--boot hd,menu=on)
    fi

    virt-install \
        --connect qemu:///system \
        --name "${WIN_XP_VM_NAME}" \
        --ram 6048 \
        --vcpus 2 \
        --import \
        --disk "path=${WIN_XP_DISK},format=qcow2,bus=ide" \
        --disk "path=${LAB_DISK_PATH},format=qcow2,bus=ide" \
        --os-variant winxp \
        --network network=default \
        --graphics spice \
        --video vga \
        "${extra_args[@]}"
}

start_apt_cacher() {
    if [[ -z "${APT_PROXY}" ]]; then
        echo "[apt-cacher] Caché APT deshabilitado en config/iso.conf"
        return 0
    fi

    if curl -s --max-time 2 "${APT_PROXY}" >/dev/null 2>&1; then
        echo "[apt-cacher] Caché ya activo"
        return 0
    fi

    echo "[apt-cacher] Iniciando caché apt..."
    run_as_host_user docker compose -f "${PROJECT_DIR}/docker-compose.yml" up -d apt-cacher >/dev/null 2>&1 || {
        echo "[apt-cacher] WARN: no se pudo iniciar el caché" >&2
        return 1
    }

    local i=0
    echo -n "[apt-cacher] Esperando"
    while ! curl -s --max-time 1 "${APT_PROXY}" >/dev/null 2>&1; do
        sleep 1
        i=$(( i + 1 ))
        echo -n "."
        [[ "${i}" -ge 20 ]] && { echo " timeout"; return 1; }
    done
    echo " listo"
}

build_target() {
    local target="${1:?missing build target}"
    local desktop_profile="${2:-${DESKTOP_PROFILE}}"

    start_apt_cacher
    DESKTOP_PROFILE="${desktop_profile}" bash "${BUILD_SCRIPT}" "${target}"
}

show_built_iso() {
    local selected_iso="$1"
    echo
    if [[ -f "${selected_iso}" ]]; then
        echo "ISO generado: ${selected_iso}"
        echo "SHA256: $(cat "${selected_iso}.sha256" 2>/dev/null || echo 'N/A')"
    else
        echo "ISO esperado: ${selected_iso:-<no encontrado>}"
        echo "SHA256: N/A"
    fi
    echo
    echo "Para grabar en USB:"
    echo "  sudo dd if=\"${selected_iso}\" of=/dev/sdX bs=4M status=progress oflag=sync"
}

start_usage() {
    cat <<EOF
Uso: $(basename "$0") [menu|run|build-gnome|build-xfce|create-disk|help]

Acciones:
  menu            abre el menú interactivo
  run             inicia el entorno de prueba con el ISO más nuevo
  build-gnome     construye el ISO con GNOME y muestra la ruta
  build-xfce      construye el ISO con XFCE y muestra la ruta
  create-disk     crea el disco NTFS lab (se usa para probar una imagen de windows xp)
  help            muestra esta ayuda
EOF
}

run_start_action() {
    local action="${1:-run}"
    local selected_iso=""

    case "${action}" in
        run)
            selected_iso="${ISO_PATH}"
            [[ -n "${selected_iso}" ]] || selected_iso="$(latest_iso_path "${OUTPUT_DIR_RESOLVED}")"
            require_iso "${selected_iso}"
            launch_winxp 1 "${selected_iso}"
            ;;
        build-gnome)
            build_target full gnome
            selected_iso="$(latest_iso_path "${OUTPUT_DIR_RESOLVED}")"
            show_built_iso "${selected_iso}"
            ;;
        build-xfce)
            build_target full xfce4
            selected_iso="$(latest_iso_path "${OUTPUT_DIR_RESOLVED}")"
            show_built_iso "${selected_iso}"
            ;;
        create-disk)
            create_lab_disk "${LAB_DISK_PATH}" 15
            ;;
        menu)
            start_interactive_menu
            ;;
        help|-h|--help)
            start_usage
            ;;
        *)
            echo "Acción desconocida: ${action}" >&2
            start_usage >&2
            return 1
            ;;
    esac
}

start_interactive_menu() {
    while true; do
        cat <<'EOF'

========================================
 Start Menu
========================================
1) Iniciar entorno de prueba
2) Generar ISO GNOME
3) Generar ISO XFCE
4) Crear disco NTFS lab
0) Salir
EOF

        read -r -p "Selecciona una opción: " option
        echo

        case "${option}" in
            1) run_start_action run; return 0 ;;
            2) run_start_action build-gnome; return 0 ;;
            3) run_start_action build-xfce; return 0 ;;
            4)
                run_start_action create-disk
                echo
                read -r -p "Presiona Enter para volver al menú..." _
                ;;
            0) return 0 ;;
            *)
                echo "Opción inválida."
                echo
                ;;
        esac
    done
}

main() {
    local action="${1-}"
    [[ -z "${action}" ]] && { start_interactive_menu; return 0; }
    run_start_action "${action}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    ensure_root "$@"
    main "$@"
fi
