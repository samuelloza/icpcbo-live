#!/usr/bin/env bash
# Helpers para hablar con la sesion grafica del usuario del concurso desde root.
# GNOME corre en Wayland: no basta DISPLAY=:0, hace falta el WAYLAND_DISPLAY real.

_gui_user="${CONTEST_SESSION_USER:-icpc}"
_gui_uid="$(id -u "${_gui_user}" 2>/dev/null || echo 1000)"
_gui_xdg="/run/user/${_gui_uid}"
_gui_bus="unix:path=${_gui_xdg}/bus"

_gui_env() {  # imprime KEY=VALUE, uno por línea
    declare -A v=(
        [XDG_RUNTIME_DIR]="${_gui_xdg}"
        [DBUS_SESSION_BUS_ADDRESS]="${_gui_bus}"
    )
    local line
    while IFS= read -r line; do
        v["${line%%=*}"]="${line#*=}"
    done < <(runuser -u "${_gui_user}" -- env \
        XDG_RUNTIME_DIR="${_gui_xdg}" DBUS_SESSION_BUS_ADDRESS="${_gui_bus}" \
        systemctl --user show-environment 2>/dev/null \
        | grep -E '^(WAYLAND_DISPLAY|DISPLAY|XAUTHORITY|XDG_CURRENT_DESKTOP)=')

    if [ -z "${v[WAYLAND_DISPLAY]:-}" ] && [ -d "${_gui_xdg}" ]; then
        local wl
        # '|| true': head cierra el pipe antes -> SIGPIPE en find/sort -> con
        # 'set -e' + pipefail heredados eso abortaria _gui_env.
        wl="$( { find "${_gui_xdg}" -maxdepth 1 -name 'wayland-[0-9]*' \
            ! -name '*.lock' -printf '%f\n' 2>/dev/null | sort | head -n1; } || true)"
        [ -n "${wl}" ] && v[WAYLAND_DISPLAY]="${wl}"
    fi
    [ -z "${v[DISPLAY]:-}" ] && v[DISPLAY]="${CONTEST_DISPLAY:-:0}"

    local k
    for k in "${!v[@]}"; do printf '%s=%s\n' "${k}" "${v[${k}]}"; done
}

# Ejecuta un comando como el usuario del concurso, con el entorno gráfico puesto.
run_user() {
    local -a e=()
    local line
    while IFS= read -r line; do [ -n "${line}" ] && e+=("${line}"); done < <(_gui_env)
    runuser -u "${_gui_user}" -- env "${e[@]}" "$@"
}

# Notificación de escritorio vía D-Bus (NO necesita display; se ve también en la
# pantalla de bloqueo). Urgencia crítica = queda hasta que la cierren.
# uso: notify_user "<texto>" ["<título>"]
notify_user() {
    local text="$1" title="${2:-Mensaje del coordinador}"
    run_user gdbus call --session \
        --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify \
        "ICPC Bolivia" 0 "dialog-information" "${title}" "${text}" \
        "[]" "{'urgency': <byte 2>}" 0 >/dev/null 2>&1
}
