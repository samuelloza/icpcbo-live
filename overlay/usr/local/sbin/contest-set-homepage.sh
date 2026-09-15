#!/usr/bin/env bash
# Fija la pagina de inicio de Firefox (aplica al reiniciar el navegador).
# El host de la URL debe estar en la allowlist de red si es externo.
set -euo pipefail

URL="${1:-}"
[ -n "${URL}" ] || { echo "uso: contest-set-homepage.sh <url>" >&2; exit 2; }

CFG="${CONTEST_FIREFOX_CFG:-/usr/lib/firefox-esr/icpcbo.cfg}"
[ -f "${CFG}" ] || { echo "no existe ${CFG}" >&2; exit 1; }

case "${URL}" in
    http://*|https://*|file://*|about:*) ;;
    *) echo "URL no valida: ${URL}" >&2; exit 1 ;;
esac

# Escapa comillas y backslashes para el string JS.
esc="$(printf '%s' "${URL}" | sed 's/[\\"]/\\&/g')"

tmp="$(mktemp)"
# Saca la homepage previa (de fabrica o de un set-homepage anterior) y el
# bloque marcado, deja todo lo demas igual.
grep -vE 'browser\.startup\.(homepage|page)"|ICPCBO set-homepage' "${CFG}" > "${tmp}"
{
    echo "// ICPCBO set-homepage ($(date -u +%FT%TZ))"
    echo "lockPref(\"browser.startup.homepage\", \"${esc}\");"
    echo "lockPref(\"browser.startup.page\", 1);"
} >> "${tmp}"

cat "${tmp}" > "${CFG}"   # preserva permisos/propietario del archivo original
rm -f "${tmp}"
echo "homepage de Firefox = ${URL} (aplica al reiniciar Firefox)"
