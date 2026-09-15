#!/usr/bin/env bash
# Estampa la región de la ISO. Corre después de 04-branding (que trunca
# /etc/issue). REGION_ROOT permite probar el hook fuera del chroot.
set -euo pipefail

ROOT="${REGION_ROOT:-}"
OWNER="${REGION_OWNER:-root}"
GROUP="${REGION_GROUP:-root}"
rp() { printf '%s%s\n' "${ROOT}" "$1"; }

install -d -o "${OWNER}" -g "${GROUP}" -m 0755 "$(rp /etc/contestiso)"
{
    printf 'REGION_ID=%q\n' "${REGION_ID:-}"
    printf 'REGION_NAME=%q\n' "${REGION_NAME:-}"
} > "$(rp /etc/contestiso/region.env)"
chmod 0644 "$(rp /etc/contestiso/region.env)"

# User-Agent con la etiqueta de región para el gate MOJ. Va como header HTTP en
# TODAS las peticiones del equipo (login, control, updates, Firefox); el gate
# solo mira que contenga "MOJ-ISO-<region>". Rotable en caliente con el comando
# firmado 'set-user-agent' y por contest-control al re-enrolar en una sede.
# ISO genérico (sin REGION_ID): usa la etiqueta bootstrap para poder alcanzar el
# login; contest-control la cambia a la de la sede tras iniciar sesión.
ua_base='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36'
ua_tag=" MOJ-ISO-${REGION_ID:-${MOJ_BOOTSTRAP_TAG:-lobby}}"
printf 'CONTEST_USER_AGENT=%q\n' "${ua_base}${ua_tag}" > "$(rp /etc/contestiso/http.env)"
chmod 0644 "$(rp /etc/contestiso/http.env)"

[ -n "${REGION_ID:-}" ] || { echo "REGION_ID vacío: ISO genérica (sin región)"; exit 0; }

printf '%s\n' "${REGION_ID}" > "$(rp /etc/contest-region)"

label="${REGION_NAME:-${REGION_ID}}"
issue="$(rp /etc/issue)"
if [ -f "${issue}" ]; then
    sed -i '/^Region: /d' "${issue}"
    printf 'Region: %s\n' "${label}" >> "${issue}"
fi

for f in "$(rp /etc/os-release)" "$(rp /usr/lib/os-release)"; do
    [ -f "${f}" ] || continue
    sed -i '/^VARIANT=/d;/^VARIANT_ID=/d' "${f}"
    printf 'VARIANT="%s"\nVARIANT_ID=%s\n' "${label}" "${REGION_ID}" >> "${f}"
done

echo "Región: ${REGION_ID} (${label})"
