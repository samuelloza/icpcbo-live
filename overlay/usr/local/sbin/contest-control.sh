#!/usr/bin/env bash
# Cliente de control remoto. Con --loop hace long-poll y ejecuta comandos
# firmados Ed25519; sin --loop hace una sola pasada.
set -euo pipefail

LOOP=0
[ "${1:-}" = "--loop" ] && LOOP=1

ENV_FILE="${CONTEST_CONTROL_ENV:-/etc/contestiso/control.env}"
IDENT_FILE="${CONTEST_CONTROL_IDENTITY:-/etc/contestiso/identity.env}"
STATE_DIR="${CONTEST_CONTROL_STATE:-/var/lib/contest-control}"
MACHINE_ID_CMD="${CONTEST_MACHINE_ID_CMD:-/usr/local/bin/stats-machine-id.sh}"
SBIN="${CONTEST_CONTROL_SBIN:-/usr/local/sbin}"
BINDING_FILE="${CONTEST_BINDING_FILE:-/etc/contestiso/binding.env}"

# systemd (StandardError=journal, SyslogLevelPrefix=yes) usa el prefijo <N>:
#   <5> notice = detalle normal   ·   <4> warning = ciclo de vida de comandos
# (clog sale tambien en la vista Journal del panel, que filtra por warning+).
log()  { echo "<5>[contest-control] $*" >&2; }
clog() { echo "<4>[contest-control] $*" >&2; }

CONTROL_SERVICE_URL=""
CONTROL_TIMEOUT="20"
CONTROL_LONGPOLL_WAIT="25"
CONTROL_STATUS_EVERY="1"
CONTROL_JOURNAL_EVERY="20"
ALLOW_VM="false"
DEFAULT_USER=""
CONTEST_CONTROL_PUBKEY="${CONTEST_CONTROL_PUBKEY:-/usr/share/contest/keys/update-signing.pub}"
# shellcheck source=/dev/null
[ -r "${ENV_FILE}" ] && . "${ENV_FILE}"
export CONTEST_SESSION_USER="${CONTEST_SESSION_USER:-${DEFAULT_USER:-icpc}}"
GROUP_ID=""
ENROLL_TOKEN=""
# shellcheck source=/dev/null
[ -r "${IDENT_FILE}" ] && . "${IDENT_FILE}"
CONTEST_USER_AGENT=""
# shellcheck source=/dev/null
[ -r "${CONTEST_HTTP_ENV:-/etc/contestiso/http.env}" ] && . "${CONTEST_HTTP_ENV:-/etc/contestiso/http.env}"
: "${CONTEST_USER_AGENT:=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36}"

[ -n "${CONTROL_SERVICE_URL}" ] || { log "CONTROL_SERVICE_URL vacio; nada que hacer"; exit 0; }
command -v curl >/dev/null 2>&1 || { log "curl no disponible"; exit 1; }
[ -r "${CONTEST_CONTROL_PUBKEY}" ] || { log "falta la clave publica ${CONTEST_CONTROL_PUBKEY}"; exit 1; }

mkdir -p "${STATE_DIR}/applied"
chmod 700 "${STATE_DIR}"
MACHINE_ID="$("${MACHINE_ID_CMD}")"
BEARER_FILE="${STATE_DIR}/bearer"
BASE_URL="${CONTROL_SERVICE_URL%/}"
BEARER=""

pyget() { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1],""))' "$1"; }

api() { # METHOD PATH [JSON] -> "<body>\n<code>"
    local method="$1" path="$2" data="${3:-}"
    local args=(--silent --show-error --max-time "$(( CONTROL_TIMEOUT + CONTROL_LONGPOLL_WAIT ))"
               -X "${method}" -w '\n%{http_code}' -A "${CONTEST_USER_AGENT}")
    [ -n "${BEARER}" ] && args+=(-H "Authorization: Bearer ${BEARER}")
    [ -n "${data}" ] && args+=(-H "Content-Type: application/json" -d "${data}")
    curl "${args[@]}" "${BASE_URL}${path}" 2>/dev/null || printf '\n000'
}

post_text() { # PATH  (body on stdin)
    curl --silent --show-error --max-time "${CONTROL_TIMEOUT}" -X POST -A "${CONTEST_USER_AGENT}" \
        -H "Authorization: Bearer ${BEARER}" -H "Content-Type: text/plain" \
        --data-binary @- "${BASE_URL}$1" >/dev/null 2>&1 || true
}

split_resp() { RESP_CODE="${1##*$'\n'}"; RESP_BODY="${1%$'\n'*}"; }

enroll() {
    [ -n "${ENROLL_TOKEN}" ] || { log "ENROLL_TOKEN vacio; no se puede enrolar"; return 1; }
    local body
    body="$(python3 -c 'import json,sys; print(json.dumps({"machine_id":sys.argv[1],"group_id":sys.argv[2],"enroll_token":sys.argv[3],"hostname":sys.argv[4]}))' \
        "${MACHINE_ID}" "${GROUP_ID}" "${ENROLL_TOKEN}" "$(hostname)")"
    BEARER=""
    split_resp "$(api POST /enroll "${body}")"
    [ "${RESP_CODE}" = "200" ] || {
        clog "ENROLL FALLO (HTTP ${RESP_CODE}) grupo='${GROUP_ID}' — ¿grupo/token no estan en groups.json del server?"
        return 1
    }
    printf '%s' "${RESP_BODY}" | pyget bearer > "${BEARER_FILE}"
    chmod 600 "${BEARER_FILE}"
    clog "enrolado como ${MACHINE_ID} (grupo ${GROUP_ID})"
}

ensure_bearer() {
    [ -s "${BEARER_FILE}" ] || enroll || return 1
    BEARER="$(cat "${BEARER_FILE}")"
}

# ISO genérico: el equipo arranca enrolado en un grupo "lobby". Cuando el
# concursante inicia sesion, el login deja en su home la sede + su enroll_token;
# aqui la maquina se RE-ENROLA en esa sede para que su coordinador la maneje.
if [ -n "${CONTEST_LOGIN_STATE_DIR:-}" ]; then
    LOGIN_STATE_DIR="${CONTEST_LOGIN_STATE_DIR}"
else
    LOGIN_HOME="$(getent passwd "${DEFAULT_USER}" | cut -d: -f6)"
    [ -n "${LOGIN_HOME}" ] || { log "DEFAULT_USER '${DEFAULT_USER}' no existe"; exit 1; }
    LOGIN_STATE_DIR="${LOGIN_HOME}/.local/state/icpcbo"
fi
REGION_ENV="${CONTEST_REGION_ENV:-/etc/contestiso/region.env}"
HTTP_ENV="${CONTEST_HTTP_ENV:-/etc/contestiso/http.env}"
UA_BASE='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36'
FIREFOX_CFG="${CONTEST_FIREFOX_CFG:-/usr/lib/firefox-esr/icpcbo.cfg}"

_read1() { head -c "${2:-256}" "$1" 2>/dev/null | tr -d '\r\n' || true; }

maybe_reenroll() {
    local rid rname rtok tok_file
    rid="$(_read1 "${LOGIN_STATE_DIR}/region.txt" 64)"
    rname="$(_read1 "${LOGIN_STATE_DIR}/region-name.txt" 128)"
    tok_file="${LOGIN_STATE_DIR}/region-enroll-token.txt"
    rtok="$(_read1 "${tok_file}" 200)"
    [ -n "${rid}" ] && [ -n "${rtok}" ] && [ "${rid}" != "${GROUP_ID}" ] || return 0

    local prev_g="${GROUP_ID}" prev_t="${ENROLL_TOKEN}"
    GROUP_ID="${rid}"; ENROLL_TOKEN="${rtok}"; BEARER=""; rm -f "${BEARER_FILE}"
    if ! enroll; then
        GROUP_ID="${prev_g}"; ENROLL_TOKEN="${prev_t}"
        log "re-enrolamiento a sede ${rid} fallo; sigo en ${prev_g}"
        ensure_bearer || true
        return 0
    fi

    umask 077
    { printf 'GROUP_ID=%q\n' "${rid}"; printf 'ENROLL_TOKEN=%q\n' "${rtok}"; } > "${IDENT_FILE}"
    umask 022; chmod 600 "${IDENT_FILE}"
    { printf 'REGION_ID=%q\n' "${rid}"; printf 'REGION_NAME=%q\n' "${rname}"; } > "${REGION_ENV}"
    chmod 644 "${REGION_ENV}"
    printf 'CONTEST_USER_AGENT=%q\n' "${UA_BASE} MOJ-ISO-${rid}" > "${HTTP_ENV}"
    chmod 644 "${HTTP_ENV}"
    # shellcheck source=/dev/null
    . "${HTTP_ENV}"
    [ -f "${FIREFOX_CFG}" ] && sed -i \
        "s|\"general.useragent.override\", \"[^\"]*\"|\"general.useragent.override\", \"${UA_BASE} MOJ-ISO-${rid}\"|" \
        "${FIREFOX_CFG}" 2>/dev/null || true
    rm -f "${tok_file}"   # consumido: no dejar el token de sede en el home
    logger -p local0.warn "ICPCBO-CONTROL: re-enrolado ${prev_g} -> ${rid}" || true
    log "re-enrolado en sede ${rid}"
    "${SBIN}/contest-session.sh" message \
        "Sede ${rname:-${rid}} activada. Si el navegador ya estaba abierto, cierralo y abrilo de nuevo." || true
}

# La homepage que entrega el login (tabla group_config del control-server) solo
# abre una ventana una vez; sin esto nunca queda fijada en icpcbo.cfg, asi que
# un reinicio de Firefox (o de la maquina, que resetea icpcbo.cfg del squashfs)
# vuelve al default de fabrica. homepage.txt vive en el home (persiste); el
# marker vive en STATE_DIR (no persiste), asi que tras cada reinicio se
# reaplica sola en el primer ciclo del loop.
maybe_apply_homepage() {
    local hp mark="${STATE_DIR}/homepage-applied"
    hp="$(_read1 "${LOGIN_STATE_DIR}/homepage.txt" 512)"
    [ -n "${hp}" ] || return 0
    [ "$(_read1 "${mark}" 512)" = "${hp}" ] && return 0
    "${SBIN}/contest-set-homepage.sh" "${hp}" >/dev/null 2>&1 && printf '%s' "${hp}" > "${mark}"
}

# telemetria
collect_editors() {
    # Conteo simple por nombre de proceso. Electron (code) infla el conteo
    # con sus helpers y las apps JVM (IntelliJ/Eclipse) no se distinguen de
    # 'java', asi que se omiten. Basta para saber si el equipo usa un editor.
    local name count out=''
    for name in geany code codium gvim vim.gtk3 nvim vim emacs kate kwrite gedit \
                nano kdevelop sublime_text subl codeblocks; do
        count="$(pgrep -x -c "${name}" 2>/dev/null || true)"
        [ "${count:-0}" -gt 0 ] 2>/dev/null \
            && out="${out}${out:+,}\"${name}\":${count}"
    done
    printf '{%s}' "${out}"
}

# Identidad del equipo que inicio sesion (la deja el login zenith en el home del
# usuario). El servidor la usa para ligar la maquina sola en el panel.
collect_login() {
    local uid tid tname uname rid rname
    uid="$(_read1 "${LOGIN_STATE_DIR}/user-id.txt" 128)"
    tid="$(_read1 "${LOGIN_STATE_DIR}/team-id.txt" 128)"
    tname="$(_read1 "${LOGIN_STATE_DIR}/team-name.txt" 256)"
    uname="$(_read1 "${LOGIN_STATE_DIR}/username.txt" 128)"
    rid="$(_read1 "${LOGIN_STATE_DIR}/region.txt" 128)"
    rname="$(_read1 "${LOGIN_STATE_DIR}/region-name.txt" 256)"
    [ -n "${uid}${tid}${tname}${uname}" ] || { printf '{}'; return; }
    python3 -c 'import json,sys
print(json.dumps({"user_id":sys.argv[1],"team_id":sys.argv[2],
                  "team_name":sys.argv[3],"username":sys.argv[4],
                  "region":sys.argv[5],"region_name":sys.argv[6]}))' \
        "${uid}" "${tid}" "${tname}" "${uname}" "${rid}" "${rname}"
}

collect_status() {
    local mem ld sw hd virt usb locked up editors login
    mem="$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{if(t)printf "%.0f",(t-a)*100/t}' /proc/meminfo 2>/dev/null)"
    ld="$(cut -d' ' -f1 /proc/loadavg 2>/dev/null)"
    sw="$(awk '/SwapTotal/{t=$2}/SwapFree/{f=$2}END{printf "%.0f",(t-f)/1024}' /proc/meminfo 2>/dev/null)"
    hd="$(df -P / 2>/dev/null | awk 'NR==2{gsub("%","",$5);print $5}')"
    virt="$(systemd-detect-virt --vm 2>/dev/null || echo none)"
    usb="$("${SBIN}/contest-usb-storage.sh" status 2>/dev/null || echo unknown)"
    locked=0; [ -e /run/contest-locked ] && locked=1
    up="$(awk '{printf "%.0f",$1}' /proc/uptime 2>/dev/null)"
    editors="$(collect_editors)"
    login="$(collect_login)"
    python3 -c 'import json,sys
v=sys.argv[1:]
def num(x):
    try: return float(x)
    except: return None
d={"mem":num(v[0]),"ld":num(v[1]),"sw":num(v[2]),"hd":num(v[3]),
   "virt":v[4],"usb":v[5],"locked":int(v[6] or 0),"uptime":num(v[7]),"hostname":v[8],
   "editors":json.loads(v[9] or "{}"),"login":json.loads(v[10] or "{}")}
print(json.dumps(d))' "${mem}" "${ld}" "${sw}" "${hd}" "${virt}" "${usb}" "${locked}" "${up}" "$(hostname)" "${editors}" "${login}"
}

send_status() {
    local s; s="$(collect_status)"
    api POST "/cmd/${GROUP_ID}/${MACHINE_ID}/status" "${s}" >/dev/null || true
    # deteccion de VM (una sola alerta)
    if [ "${ALLOW_VM}" != "true" ] && [ ! -e "${STATE_DIR}/alerted-vm" ]; then
        local virt; virt="$(printf '%s' "${s}" | pyget virt)"
        if [ -n "${virt}" ] && [ "${virt}" != "none" ]; then
            "${SBIN}/contest-alert.sh" vm.detected "${virt}" 2>/dev/null || true
            : > "${STATE_DIR}/alerted-vm"
        fi
    fi
}

send_journal() {
    # El panel muestra esto en "Journal": el log del propio contest-control
    # (actividad de comandos) + los avisos del sistema.
    {
        echo "=== contest-control (ultimas lineas) ==="
        journalctl -u contest-control.service -b --no-pager -n 80 2>/dev/null
        echo "=== avisos del sistema ==="
        journalctl -p warning -b --no-pager 2>/dev/null | tail -c 4000
    } | post_text "/cmd/${GROUP_ID}/${MACHINE_ID}/journal"
}

# reconciliacion de estado
PHASE_FILE="${CONTEST_PHASE_FILE:-/run/contest-phase}"
PHASE_LOCK_MARK="${STATE_DIR}/phase-locked"

reconcile_phase() {
    local phase="$1" prev=''
    [ -n "${phase}" ] || return 0
    [ -r "${PHASE_FILE}" ] && prev="$(cat "${PHASE_FILE}")"
    [ "${phase}" = "${prev}" ] && return 0

    printf '%s\n' "${phase}" > "${PHASE_FILE}" 2>/dev/null || true
    logger -p local0.info "ICPCBO-PHASE: ${prev:-?} -> ${phase}" || true
    case "${phase}" in
        practice) "${SBIN}/contest-session.sh" message "El concurso pasa a PRACTICA." || true ;;
        live)     "${SBIN}/contest-session.sh" message "El concurso EMPEZO. Mucha suerte." || true ;;
        frozen)   "${SBIN}/contest-session.sh" message "Marcador CONGELADO." || true ;;
        ended)
            "${SBIN}/contest-session.sh" message "El concurso TERMINO. Pueden dejar de escribir." || true
            : > "${PHASE_LOCK_MARK}"
            "${SBIN}/contest-session.sh" lock || true ;;
    esac
    # Al reabrir (practice/live tras un 'ended') se quita solo el bloqueo de fase.
    if [ "${phase}" != "ended" ] && [ -e "${PHASE_LOCK_MARK}" ]; then
        rm -f "${PHASE_LOCK_MARK}"
        "${SBIN}/contest-session.sh" unlock || true
    fi
}

reconcile_meta() {
    local meta="$1" lock binding phase
    lock="$(printf '%s' "${meta}" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("meta",{}).get("lock_state",""))
except Exception: print("")')"
    if [ "${lock}" = "1" ] && [ ! -e /run/contest-locked ]; then
        "${SBIN}/contest-session.sh" lock || true
    elif [ "${lock}" = "0" ] && [ -e /run/contest-locked ]; then
        "${SBIN}/contest-session.sh" unlock || true
    fi
    phase="$(printf '%s' "${meta}" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("meta",{}).get("phase",""))
except Exception: print("")')"
    reconcile_phase "${phase}"
    binding="$(printf '%s' "${meta}" | python3 -c 'import json,sys
try:
    b=json.load(sys.stdin).get("meta",{}).get("binding") or {}
    print("\n".join("%s=%s"%(k.upper(),str(b.get(k) or "")) for k in ("name","org","seat","country","user_id")))
except Exception: pass')"
    if [ -n "${binding}" ]; then
        { echo "# generado por contest-control.sh"; printf '%s\n' "${binding}" \
            | sed 's/^\([A-Z_]*\)=/TEAM_\1=/'; } > "${BINDING_FILE}" 2>/dev/null || true
    fi
}

# ejecucion de un comando
handle_command() {
    local resp="$1" nonce payload_b64 signature_b64 work
    nonce="$(printf '%s' "${resp}" | pyget nonce)"
    payload_b64="$(printf '%s' "${resp}" | pyget payload_b64)"
    signature_b64="$(printf '%s' "${resp}" | pyget signature)"
    [ -n "${nonce}" ] && [ -n "${payload_b64}" ] && [ -n "${signature_b64}" ] || return 0

    clog "comando recibido: nonce=${nonce}"
    work="$(mktemp -d)"
    printf '%s' "${payload_b64}"   | openssl base64 -d -A > "${work}/cmd.json"
    printf '%s' "${signature_b64}" | openssl base64 -d -A > "${work}/cmd.sig"
    if ! openssl pkeyutl -verify -pubin -rawin -inkey "${CONTEST_CONTROL_PUBKEY}" \
            -in "${work}/cmd.json" -sigfile "${work}/cmd.sig" >/dev/null 2>&1; then
        clog "RECHAZADO nonce=${nonce}: firma invalida (¿pubkey del ISO != key del server?)"
        rm -rf "${work}"; return 0
    fi

    eval "$(python3 - "${work}/cmd.json" "${MACHINE_ID}" "${GROUP_ID}" <<'PY'
import base64, datetime, json, shlex, sys
d = json.load(open(sys.argv[1])); mid, gid = sys.argv[2], sys.argv[3]
now = datetime.datetime.now(datetime.timezone.utc)
reason = ""
if d.get("group_id") != gid:
    reason = f"grupo del comando ({d.get('group_id')}) != grupo del equipo ({gid})"
elif d.get("machine_id") not in (mid, "*"):
    reason = f"maquina del comando ({d.get('machine_id')}) != esta ({mid})"
else:
    try:
        exp = datetime.datetime.strptime(d.get("expires_at",""), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
        # +24h de tolerancia: el reloj del equipo puede estar mal (sin NTP) y no
        # se debe descartar un comando recien firmado por eso. El replay lo corta
        # el registro de nonces aplicados.
        if (exp + datetime.timedelta(hours=24)) <= now:
            reason = f"expirado (expires_at={d.get('expires_at')}, reloj equipo={now:%Y-%m-%dT%H:%M:%SZ})"
    except Exception as e:
        reason = f"expires_at ilegible: {e}"
print(f"CMD_OK={'1' if not reason else '0'}")
print("CMD_REJECT=" + shlex.quote(reason))
print("CMD_ACTION=" + shlex.quote(str(d.get("action",""))))
print("CMD_ARGS_B64=" + shlex.quote(base64.b64encode(json.dumps(d.get("args",{})).encode()).decode()))
PY
)"
    rm -rf "${work}"
    [ "${CMD_OK:-0}" = "1" ] || { clog "RECHAZADO nonce=${nonce} action=${CMD_ACTION:-?}: ${CMD_REJECT:-motivo desconocido}"; return 0; }

    ack() {
        local _b _c
        _b="$(api POST "/cmd/${GROUP_ID}/${MACHINE_ID}/ack" \
            "$(python3 -c 'import json,sys;print(json.dumps({"nonce":sys.argv[1],"status":sys.argv[2],"detail":sys.argv[3]}))' \
                "${nonce}" "$1" "${2:-}")")" || _b=$'\n000'
        _c="${_b##*$'\n'}"
        [ "${_c}" = "200" ] || clog "ACK nonce=${nonce} status=$1 -> el server respondio HTTP ${_c}"
    }

    if [ -e "${STATE_DIR}/applied/${nonce}" ]; then
        clog "nonce=${nonce} ya aplicado antes; se ackea como duplicado"
        ack duplicate; return 0
    fi

    arg() { printf '%s' "${CMD_ARGS_B64}" | openssl base64 -d -A | pyget "$1"; }
    local status="ok" detail="" need_reboot=0 need_poweroff=0
    case "${CMD_ACTION}" in
        lock)          "${SBIN}/contest-session.sh" lock                 || status=error ;;
        unlock)        "${SBIN}/contest-session.sh" unlock              || status=error ;;
        logout)        "${SBIN}/contest-session.sh" logout              || status=error ;;
        message)       "${SBIN}/contest-session.sh" message "$(arg text)" || status=error ;;
        set-wallpaper) "${SBIN}/contest-set-wallpaper.sh" "$(arg url)"    || status=error ;;
        usb-block)     "${SBIN}/contest-usb-storage.sh" block            || status=error ;;
        usb-unblock)   "${SBIN}/contest-usb-storage.sh" unblock          || status=error ;;
        net-open)      "${SBIN}/contest-net.sh" open                     || status=error ;;
        net-lock)      "${SBIN}/contest-net.sh" lock                     || status=error ;;
        donottouch)    : > "${STATE_DIR}/frozen"
                       systemctl start contest-freeze-guard.service 2>/dev/null || true ;;
        cantouch)      rm -f "${STATE_DIR}/frozen"
                       systemctl stop contest-freeze-guard.service 2>/dev/null || true ;;
        precontest)
            "${SBIN}/contest-session.sh" lock || status=error
            "${SBIN}/contest-usb-storage.sh" block || status=error
            ;;
        set-allowlist)
            printf '%s' "${CMD_ARGS_B64}" | openssl base64 -d -A | python3 -c '
import json,sys
hosts=json.load(sys.stdin).get("hosts",[])
open("/etc/contestiso/allowlist.conf","w").write("# Regenerado por set-allowlist\n"+"\n".join(str(h) for h in hosts)+"\n")'
            "${SBIN}/contest-allowlist-apply.sh" || status=error ;;
        set-user-agent)
            # Rota el User-Agent (etiqueta MOJ) sin re-buildear. Aplica al proximo
            # arranque/login: los scripts leen /etc/contestiso/http.env al iniciar.
            printf '%s' "${CMD_ARGS_B64}" | openssl base64 -d -A | python3 -c '
import json,shlex,sys
ua=str(json.load(sys.stdin).get("user_agent","")).strip()
if not ua: raise SystemExit("user_agent vacio")
open("/etc/contestiso/http.env","w").write("CONTEST_USER_AGENT="+shlex.quote(ua)+"\n")' \
                && chmod 0644 /etc/contestiso/http.env || status=error ;;
        set-homepage)
            # Cambia la pagina de inicio de Firefox sin re-buildear. Aplica
            # cuando el concursante reinicia el navegador.
            if "${SBIN}/contest-set-homepage.sh" "$(arg url)"; then
                detail="aplica al reiniciar Firefox"
            else
                status=error
            fi ;;
        screenshot)
            shot="$(mktemp --suffix=.png)"
            if "${SBIN}/contest-screenshot.sh" "${shot}" && [ -s "${shot}" ]; then
                curl --silent --show-error --max-time 30 -A "${CONTEST_USER_AGENT}" \
                    -H "Authorization: Bearer ${BEARER}" -H "Content-Type: image/png" \
                    --data-binary @"${shot}" \
                    "${BASE_URL}/cmd/${GROUP_ID}/${MACHINE_ID}/screenshot" >/dev/null \
                    || { status=error; detail="subida fallo"; }
            else
                status=error; detail="captura fallo"
            fi
            rm -f "${shot}" ;;
        collect-home)
            # Empaqueta SOLO los archivos/carpetas VISIBLES de /home/<usuario> y
            # lo sube al control-server. Para juntar el código de cada equipo al
            # terminar el concurso.
            #   --exclude='.*' / '*/.*' : descarta cualquier entrada oculta
            #   (dotfiles y dotdirs) a cualquier profundidad -> nada de .config,
            #   .cache, .mozilla, .vscode, .git, etc.
            #   node_modules queda fuera: es regenerable y puede reventar el tope.
            tb="$(mktemp --suffix=.tgz)"
            hu="${CONTEST_HOME_USER:-${DEFAULT_USER:-icpc}}"
            tid="$(_read1 "${LOGIN_STATE_DIR}/team-id.txt" 64)"
            tar czf "${tb}" -C /home \
                --exclude='.*' --exclude='*/.*' --exclude='node_modules' \
                "${hu}" 2>/dev/null || true
            if [ -s "${tb}" ] && gzip -t "${tb}" 2>/dev/null; then
                curl --silent --show-error --max-time 180 -A "${CONTEST_USER_AGENT}" \
                    -H "Authorization: Bearer ${BEARER}" -H "Content-Type: application/gzip" \
                    -H "X-Team-Id: ${tid}" --data-binary @"${tb}" \
                    "${BASE_URL}/cmd/${GROUP_ID}/${MACHINE_ID}/home" >/dev/null \
                    && detail="home de ${hu} enviado${tid:+ (equipo ${tid})}" \
                    || { status=error; detail="subida fallo"; }
            else
                status=error; detail="no se pudo empaquetar /home/${hu}"
            fi
            rm -f "${tb}" ;;
        unlock-root)
            # DEBUG remoto: habilita root con la contraseña dada. Solo superadmin
            # (lo valida el server). Viaja en claro por el canal de control.
            pw="$(arg password)"
            if [ -n "${pw}" ] && printf 'root:%s\n' "${pw}" | chpasswd && passwd -u root >/dev/null 2>&1; then
                detail="root habilitado"
                logger -p local0.warn "ICPCBO-CONTROL: root DESBLOQUEADO por el panel" || true
            else
                status=error; detail="no se pudo habilitar root"
            fi ;;
        lock-root)
            if passwd -l root >/dev/null 2>&1; then
                detail="root bloqueado"
                logger -p local0.warn "ICPCBO-CONTROL: root re-bloqueado por el panel" || true
            else
                status=error
            fi ;;
        reset-home)
            : > "${STATE_DIR}/reset-home"
            if "${SBIN}/contest-reset-home.sh" --now; then
                detail="/home limpiado; escritorio reiniciado (sin reboot)"
            else
                status=error; detail="fallo la limpieza de /home"
            fi ;;
        reboot)        need_reboot=1 ;;
        poweroff)      need_poweroff=1 ;;
        *)             status=error; detail="accion desconocida: ${CMD_ACTION}" ;;
    esac

    [ "${status}" = "ok" ] && : > "${STATE_DIR}/applied/${nonce}"
    ack "${status}" "${detail}"
    clog "accion=${CMD_ACTION} nonce=${nonce} -> ${status}${detail:+ (${detail})}"
    # Empuja el journal al panel tras CADA comando (antes de un reboot/poweroff),
    # para que la vista Journal del panel refleje que paso, sin esperar al ciclo.
    send_journal || true
    [ "${need_reboot}" = "1" ] && { sync; systemctl reboot; }
    [ "${need_poweroff}" = "1" ] && { sync; systemctl poweroff; }
    return 0
}

poll_once() {
    local wait="$1" resp
    split_resp "$(api GET "/cmd/${GROUP_ID}/${MACHINE_ID}?wait=${wait}")"
    case "${RESP_CODE}" in
        200) ;;
        204) return 1 ;;
        401) clog "bearer invalido (HTTP 401); re-enrolando"; rm -f "${BEARER_FILE}"; ensure_bearer || true; return 1 ;;
        000) clog "sin respuesta del control-server (${BASE_URL}); ¿red/allowlist/DNS?"; return 2 ;;
        *)   clog "poll HTTP ${RESP_CODE} inesperado"; return 2 ;;
    esac
    reconcile_meta "${RESP_BODY}"
    if printf '%s' "${RESP_BODY}" | pyget nonce | grep -q .; then
        handle_command "${RESP_BODY}"
        return 0
    fi
    return 1
}

maybe_reenroll   # sede persistida de una sesion anterior
[ -n "${GROUP_ID}" ] || { log "GROUP_ID vacio y el login aun no asigno una sede"; exit 0; }
ensure_bearer || exit 0
maybe_apply_homepage

# El flag 'frozen' puede sobrevivir un reinicio (persistencia): repone el aviso.
[ -e "${STATE_DIR}/frozen" ] && { systemctl start contest-freeze-guard.service 2>/dev/null || true; }

if [ "${LOOP}" = "0" ]; then
    send_status
    poll_once 0 || true
    exit 0
fi

log "loop de control iniciado (grupo ${GROUP_ID}, wait=${CONTROL_LONGPOLL_WAIT}s)"
i=0
while :; do
    i=$(( i + 1 ))
    maybe_reenroll
    maybe_apply_homepage
    [ $(( i % CONTROL_STATUS_EVERY )) -eq 0 ] && send_status
    [ $(( i % CONTROL_JOURNAL_EVERY )) -eq 0 ] && send_journal
    rc=0; poll_once "${CONTROL_LONGPOLL_WAIT}" || rc=$?
    case "${rc}" in
        0) sleep 1 ;;      # hubo comando: drena rapido
        2) sleep 15 ;;     # error de red
        *) sleep 3 ;;
    esac
done
