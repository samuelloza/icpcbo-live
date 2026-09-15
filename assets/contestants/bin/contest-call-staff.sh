#!/usr/bin/env bash
set -euo pipefail

DROP="/run/contest-call-staff"

if [ ! -d "${DROP}" ]; then
    zenity --error --title "ICPC Bolivia" \
        --text "El aviso al staff no está disponible en este equipo." 2>/dev/null || true
    exit 1
fi

# Cancelar el diálogo aborta el aviso; aceptar (aunque vacío) lo envía.
reason="$(zenity --entry --width=420 --title "Llamar al staff" \
    --text "Describe brevemente qué necesitas (opcional):" 2>/dev/null)" || exit 0

f="${DROP}/req-$(date +%s)-$$"
if ! printf '%s\n' "${reason}" > "${f}" 2>/dev/null; then
    zenity --error --title "ICPC Bolivia" \
        --text "No se pudo enviar el aviso." 2>/dev/null || true
    exit 1
fi

zenity --info --width=420 --title "ICPC Bolivia" \
    --text "El Staff fue notificado y se acercará." 2>/dev/null || true
