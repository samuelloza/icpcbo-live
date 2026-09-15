#!/usr/bin/env bash
# Descarga una imagen y la fija como fondo (GNOME y XFCE). El host de la
# URL debe estar en la allowlist de red.
set -euo pipefail

URL="${1:?uso: contest-set-wallpaper.sh <url>}"
USER_NAME="${CONTEST_WALLPAPER_USER:-icpc}"
DEST_DIR="/home/${USER_NAME}/.local/state/icpcbo"
DEST="${DEST_DIR}/admin-wallpaper.img"

export CONTEST_SESSION_USER="${USER_NAME}"
# shellcheck source=/dev/null
. "${CONTEST_GUI_LIB:-/usr/local/lib/contest/gui.sh}"

install -d -o "${USER_NAME}" -g "${USER_NAME}" -m 0755 "${DEST_DIR}"

CONTEST_USER_AGENT=""
# shellcheck source=/dev/null
[ -r "${CONTEST_HTTP_ENV:-/etc/contestiso/http.env}" ] && . "${CONTEST_HTTP_ENV:-/etc/contestiso/http.env}"
: "${CONTEST_USER_AGENT:=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36}"

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT
curl --fail --silent --show-error --location --max-time 30 -A "${CONTEST_USER_AGENT}" "${URL}" -o "${tmp}"
[ -s "${tmp}" ] || { echo "descarga vacia: ${URL}" >&2; exit 1; }
magic="$(od -An -tx1 -N8 "${tmp}" | tr -d ' \n')"
case "${magic}" in
    ffd8ff*)      ;;  # jpeg
    89504e470d0a1a0a) ;;  # png
    4749463839*|4749463837*) ;;  # gif
    52494646*)    ;;  # riff/webp
    *) grep -qi '<svg' "${tmp}" || { echo "no parece una imagen: ${URL}" >&2; exit 1; } ;;
esac

install -o "${USER_NAME}" -g "${USER_NAME}" -m 0644 "${tmp}" "${DEST}"

if run_user gsettings set org.gnome.desktop.background picture-uri "file://${DEST}" 2>/dev/null; then
    run_user gsettings set org.gnome.desktop.background picture-uri-dark "file://${DEST}" 2>/dev/null || true
    run_user gsettings set org.gnome.desktop.background picture-options "scaled" 2>/dev/null || true
fi

if command -v xfconf-query >/dev/null 2>&1; then
    run_user bash -c '
        for p in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep "/last-image$"); do
            xfconf-query -c xfce4-desktop -p "$p" -s "'"${DEST}"'"
        done' 2>/dev/null || true
fi

echo "wallpaper aplicado desde ${URL}"
