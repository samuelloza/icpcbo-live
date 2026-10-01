#!/usr/bin/env bash
# Algunas tarjetas wifi PCI no levantan el link en frio (probaron mal el
# driver al primer boot) y quedan invisibles para NetworkManager/GNOME aunque
# el mini-deploy sí las vea. Se hace unbind + PCI reset + rebind (o reprobe)
# de cualquier controlador de red PCI antes de que arranque NetworkManager.
# Lo usa contest-wifi-pci-reset.service.
set -euo pipefail

SYS_PCI="${CONTEST_PCI_SYSFS:-/sys/bus/pci}"

reset_failed_pci_wifi() {
    local dev class bdf driver_path driver

    for dev in "${SYS_PCI}"/devices/*; do
        [ -r "${dev}/class" ] || continue

        class="$(cat "${dev}/class")"

        # 0x0280xx = Network controller. Es la clase PCI habitual de wifi.
        case "${class}" in
            0x0280*) ;;
            *) continue ;;
        esac

        bdf="$(basename "${dev}")"
        echo "Controlador de red PCI detectado: ${bdf}"

        driver_path="$(readlink -f "${dev}/driver" 2>/dev/null || true)"

        if [ -n "${driver_path}" ]; then
            driver="$(basename "${driver_path}")"
            echo "Driver: ${driver}"

            if [ -w "${driver_path}/unbind" ]; then
                echo "${bdf}" > "${driver_path}/unbind"
                sleep 1
            fi
        else
            driver=""
            echo "Actualmente sin driver asociado."
        fi

        if [ -w "${dev}/reset" ]; then
            echo "Realizando PCI reset..."
            echo 1 > "${dev}/reset"
            sleep 2
        else
            echo "No soporta PCI reset."
            continue
        fi

        if [ -n "${driver}" ] && [ -w "${SYS_PCI}/drivers/${driver}/bind" ]; then
            echo "${bdf}" > "${SYS_PCI}/drivers/${driver}/bind"
        elif [ -w "${SYS_PCI}/drivers_probe" ]; then
            echo "Solicitando reprobe..."
            echo "${bdf}" > "${SYS_PCI}/drivers_probe"
        fi

        sleep 2
    done
}

reset_failed_pci_wifi
