#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_SCRIPT="${SCRIPT_DIR}/build.sh"

# shellcheck source=../config/iso.conf
source "${PROJECT_DIR}/config/iso.conf"

if [[ "${OUTPUT_DIR}" == /work/* ]] && { [[ ! -d /work ]] || [[ ! -w /work ]]; }; then
    OUTPUT_DIR="${PROJECT_TMP_DIR}/output"
fi

if [[ -e "${OUTPUT_DIR}" && ! -w "${OUTPUT_DIR}" ]]; then
    OUTPUT_DIR="${PROJECT_TMP_DIR}/output"
elif [[ ! -e "${OUTPUT_DIR}" && ! -w "$(dirname "${OUTPUT_DIR}")" ]]; then
    OUTPUT_DIR="${PROJECT_TMP_DIR}/output"
fi


pause_menu() {
    echo
    read -r -p "Presiona Enter para volver al menú..." _
}

run_menu_action() {
    local action="$1"
    case "${action}" in
        runtime)
            bash "${BUILD_SCRIPT}" runtime
            ;;
        publish-update)
            bash "${BUILD_SCRIPT}" publish-update
            ;;
        build-gnome)
            DESKTOP_PROFILE=gnome bash "${BUILD_SCRIPT}" full
            ;;
        build-xfce)
            DESKTOP_PROFILE=xfce4 bash "${BUILD_SCRIPT}" full
            ;;
        test-grub)
            bash "${PROJECT_DIR}/tests/check-grub-config.sh"
            ;;
        help|-h|--help)
            cat <<EOF
Uso: build-menu.sh [accion]

Acciones:
  runtime           Ejecuta build hasta runtime
  publish-update    Publica runtime versionado en updates/
  build-gnome        Ejecuta build completo con GNOME
  build-xfce         Ejecuta build completo con XFCE
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
1) Build hasta runtime
2) Publicar update
3) Build completo GNOME
4) Build completo XFCE
5) Test de GRUB
0) Salir
EOF

    read -r -p "Selecciona una opción [0-5]: " option
    echo

    case "${option}" in
        1)
            run_menu_action runtime
            pause_menu
            ;;
        2)
            run_menu_action publish-update
            pause_menu
            ;;
        3)
            run_menu_action build-gnome
            pause_menu
            ;;
        4)
            run_menu_action build-xfce
            pause_menu
            ;;
        5)
            run_menu_action test-grub
            pause_menu
            ;;
        0)
            exit 0
            ;;
        *)
            echo "Opción inválida."
            pause_menu
            ;;
    esac
done
