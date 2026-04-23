#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_SCRIPT="${SCRIPT_DIR}/build.sh"

# shellcheck source=../config/iso.conf
source "${PROJECT_DIR}/config/iso.conf"

if [[ -f "${PROJECT_DIR}/config/iso.local.conf" ]]; then
    # shellcheck source=/dev/null
    source "${PROJECT_DIR}/config/iso.local.conf"
fi

if [[ "${OUTPUT_DIR}" == /work/* ]] && { [[ ! -d /work ]] || [[ ! -w /work ]]; }; then
    OUTPUT_DIR="${PROJECT_DIR}/output"
fi

if [[ -e "${OUTPUT_DIR}" && ! -w "${OUTPUT_DIR}" ]]; then
    OUTPUT_DIR="${PROJECT_DIR}/output-local"
elif [[ ! -e "${OUTPUT_DIR}" && ! -w "$(dirname "${OUTPUT_DIR}")" ]]; then
    OUTPUT_DIR="${PROJECT_DIR}/output-local"
fi

GRUB_PREVIEW_DIR="${OUTPUT_DIR}/grub-preview"

pause_menu() {
    echo
    read -r -p "Presiona Enter para volver al menú..." _
}

show_file_if_exists() {
    local file="$1"

    if [[ ! -f "${file}" ]]; then
        echo "No existe: ${file}"
        echo "Primero genera el preview de GRUB."
        return 0
    fi

    echo
    echo "===== ${file} ====="
    cat "${file}"
}

run_menu_action() {
    local action="$1"

    case "${action}" in
        grub-preview)
            bash "${BUILD_SCRIPT}" grub-preview
            ;;
        show-iso-grub)
            show_file_if_exists "${GRUB_PREVIEW_DIR}/boot/grub/grub.cfg"
            ;;
        show-runtime-grub)
            show_file_if_exists "${GRUB_PREVIEW_DIR}/${CONTEST_DIR}/grub-entry.cfg"
            ;;
        runtime)
            bash "${BUILD_SCRIPT}" runtime
            ;;
        publish-update)
            bash "${BUILD_SCRIPT}" publish-update
            ;;
        full)
            bash "${BUILD_SCRIPT}" full
            ;;
        test-grub)
            bash "${PROJECT_DIR}/tests/check-grub-config.sh"
            ;;
        help|-h|--help)
            cat <<EOF
Uso: build-menu.sh [accion]

Acciones:
  grub-preview      Genera grub.cfg + grub-entry.cfg + ISO preview booteable
  show-iso-grub     Muestra output/grub-preview/boot/grub/grub.cfg
  show-runtime-grub Muestra output/grub-preview/${CONTEST_DIR}/grub-entry.cfg
  runtime           Ejecuta build hasta runtime
  publish-update    Publica runtime versionado en updates/
  full              Ejecuta build completo
  test-grub         Corre tests/check-grub-config.sh
EOF
            ;;
        *)
            echo "Acción desconocida: ${action}" >&2
            return 1
            ;;
    esac
}

if [[ $# -gt 0 ]]; then
    run_menu_action "$1"
    exit 0
fi

while true; do
    cat <<'EOF'

========================================
 Build Menu
========================================
1) Generar GRUB + ISO preview
2) Ver grub.cfg generado
3) Ver grub-entry.cfg generado
4) Build hasta runtime
 5) Publicar update
 6) Build completo
 7) Test de GRUB
 8) Salir
EOF

    read -r -p "Selecciona una opción [1-8]: " option
    echo

    case "${option}" in
        1)
            run_menu_action grub-preview
            pause_menu
            ;;
        2)
            run_menu_action show-iso-grub
            pause_menu
            ;;
        3)
            run_menu_action show-runtime-grub
            pause_menu
            ;;
        4)
            run_menu_action runtime
            pause_menu
            ;;
        5)
            run_menu_action publish-update
            pause_menu
            ;;
        6)
            run_menu_action full
            pause_menu
            ;;
        7)
            run_menu_action test-grub
            pause_menu
            ;;
        8)
            exit 0
            ;;
        *)
            echo "Opción inválida."
            pause_menu
            ;;
    esac
done
