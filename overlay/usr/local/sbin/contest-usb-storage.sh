#!/usr/bin/env bash
# Bloquea/permite el almacenamiento externo (USB, USB3/UAS). No toca teclado ni
# mouse. Lo usa contest-usb-policy.service al arranque y la accion usb-block /
# usb-unblock del control remoto.
set -euo pipefail

DROPIN="${CONTEST_USB_DROPIN:-/etc/modprobe.d/contest-usb-storage.conf}"
POLICY="${CONTEST_USB_POLICY:-/etc/contestiso/usb-policy.env}"
MODULES=(usb_storage uas)

usage() { echo "uso: $0 {block|unblock|apply|reload|status}" >&2; exit 2; }
[ "$#" -eq 1 ] || usage

write_dropin() {
    cat > "${DROPIN}" <<'EOF'
# Generado por contest-usb-storage.sh - almacenamiento USB bloqueado.
install usb_storage /bin/true
install uas /bin/true
EOF
}

reload_usb() {
    local m
    # Si el modulo esta en uso (disco USB montado en el momento del bloqueo),
    # modprobe -r falla aqui; contest-usb-reload.timer reintenta cada 30s hasta
    # que se libere, asi que no hace falta expulsarlo a la fuerza.
    for m in "${MODULES[@]}"; do modprobe -r "${m}" 2>/dev/null || true; done
    udevadm trigger --subsystem-match=usb --action=add 2>/dev/null || true
}

block() {
    write_dropin
    printf 'USB_STORAGE=blocked\n' > "${POLICY}"
    reload_usb
    echo "almacenamiento USB: BLOQUEADO"
}

unblock() {
    rm -f "${DROPIN}"
    printf 'USB_STORAGE=allowed\n' > "${POLICY}"
    local m
    for m in "${MODULES[@]}"; do modprobe "${m}" 2>/dev/null || true; done
    udevadm trigger --subsystem-match=usb --action=add 2>/dev/null || true
    echo "almacenamiento USB: PERMITIDO"
}

apply() {
    local want="blocked"
    if [ -r "${POLICY}" ]; then
        # shellcheck source=/dev/null
        . "${POLICY}"
        want="${USB_STORAGE:-blocked}"
    fi
    [ "${want}" = "allowed" ] && unblock || block
}

# Reintento periodico (contest-usb-reload.timer): si el drop-in esta puesto,
# vuelve a intentar descargar el modulo. No-op si ya esta descargado o si la
# politica es "allowed" (sin drop-in).
reload() {
    [ -f "${DROPIN}" ] || return 0
    reload_usb
}

case "$1" in
    block)   block ;;
    unblock) unblock ;;
    apply)   apply ;;
    reload)  reload ;;
    status)  [ -f "${DROPIN}" ] && echo blocked || echo allowed ;;
    *)       usage ;;
esac
