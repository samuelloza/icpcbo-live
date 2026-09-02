#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="${PROJECT_DIR}/tests/fixtures/auth"
PARSER="${PROJECT_DIR}/assets/contestants/bin/contestants-login-parse-response.py"
WALLPAPER="${PROJECT_DIR}/assets/contestants/bin/contestants-login-write-wallpaper.py"
GNOME_LOGIN="${PROJECT_DIR}/assets/contestants/bin/contestants-login-gnome.sh"
XFCE_LOGIN="${PROJECT_DIR}/assets/contestants/bin/contestants-login-xfce.sh"
GNOME_AUTOSTART="${PROJECT_DIR}/assets/contestants/bin/gnome-autostart.sh"
XFCE_AUTOSTART="${PROJECT_DIR}/assets/contestants/bin/xfce-autostart.sh"
STATS_PAYLOAD="${PROJECT_DIR}/overlay/usr/local/bin/stats-build-payload.py"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local label="$3"

    [[ "${actual}" == "${expected}" ]] || \
        fail "${label}: expected '${expected}', got '${actual}'"
}

assert_contains() {
    grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"
}

assert_file_mode() {
    local path="$1"
    local expected="$2"

    assert_equals "${expected}" "$(stat -c %a "${path}")" "mode for ${path}"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

parse_fixture() {
    local fixture="$1"
    local required="$2"
    local env_file="${tmp_dir}/parsed.env"

    python3 "${PARSER}" "${FIXTURES}/${fixture}" 200 fallback-user "${required}" > "${env_file}"
    # shellcheck source=/dev/null
    source "${env_file}"
}

test_parser() {
    parse_fixture camel-case.json true
    assert_equals "1" "${AUTH_OK}" "camel-case auth"
    assert_equals "bo-17" "${AUTH_TEAM_ID}" "camel-case team id"
    assert_equals "Altiplano" "${AUTH_TEAM_NAME}" "camel-case team name"

    parse_fixture snake-case.json true
    assert_equals "bo_18" "${AUTH_TEAM_ID}" "snake-case team id"
    assert_equals "Andes" "${AUTH_TEAM_NAME}" "snake-case team name"

    parse_fixture nested-team.json true
    assert_equals "bo.19" "${AUTH_TEAM_ID}" "nested team id"
    assert_equals 'Cóndor <&> "Rojo"' "${AUTH_TEAM_NAME}" "special team name"

    parse_fixture legacy.json false
    assert_equals "1" "${AUTH_OK}" "legacy compatibility enabled"
    assert_equals "legacy-20" "${AUTH_TEAM_ID}" "legacy team id fallback"
    assert_equals "Equipo legado" "${AUTH_TEAM_NAME}" "legacy team name fallback"

    parse_fixture legacy.json true
    assert_equals "0" "${AUTH_OK}" "legacy compatibility disabled"
    assert_contains "${tmp_dir}/parsed.env" "identificador obligatorio"

    parse_fixture missing-team-id.json true
    assert_equals "0" "${AUTH_OK}" "required team id"

    parse_fixture invalid-team-id.json true
    assert_equals "0" "${AUTH_OK}" "invalid team id"

    parse_fixture false-string.json true
    assert_equals "0" "${AUTH_OK}" "string false is not truthy"

    parse_fixture invalid-json.json true
    assert_equals "0" "${AUTH_OK}" "invalid JSON"

    printf '[]\n' > "${tmp_dir}/array.json"
    python3 "${PARSER}" "${tmp_dir}/array.json" 200 fallback-user true > "${tmp_dir}/parsed.env"
    # shellcheck source=/dev/null
    source "${tmp_dir}/parsed.env"
    assert_equals "0" "${AUTH_OK}" "non-object JSON"
}

test_atomic_persistence() {
    local login_script="$1"
    local profile="$2"
    local state_dir="${tmp_dir}/${profile}-state"
    local response="${tmp_dir}/${profile}-response.json"

    printf '{"ok":true}\n' > "${response}"
    CONTEST_LOGIN_LIBRARY_ONLY=1 \
    CONTEST_LOGIN_STATE_DIR="${state_dir}" \
    CONTEST_AUTH_ENV_FILE="${tmp_dir}/missing-auth.env" \
    bash -c '
        set -euo pipefail
        source "$1"
        persist_login_state user user-1 "Display Name" team-1 "Team Name" "$2"
    ' bash "${login_script}" "${response}"

    assert_equals "team-1" "$(<"${state_dir}/team-id.txt")" "${profile} team id"
    assert_equals "Team Name" "$(<"${state_dir}/team-name.txt")" "${profile} team name"
    assert_file_mode "${state_dir}" 700
    for path in username.txt user-id.txt display-name.txt team-id.txt team-name.txt auth-response.json; do
        assert_file_mode "${state_dir}/${path}" 600
    done
    if find "${state_dir}" -maxdepth 1 \
        \( -name '.identity.*' -o -name '.auth-response.*' \) | grep -q .; then
        fail "${profile} left atomic-write temporary files"
    fi

    printf '{"ok":true,"second":true}\n' > "${response}"
    CONTEST_LOGIN_LIBRARY_ONLY=1 \
    CONTEST_LOGIN_STATE_DIR="${state_dir}" \
    CONTEST_AUTH_ENV_FILE="${tmp_dir}/missing-auth.env" \
    bash -c '
        set -euo pipefail
        source "$1"
        persist_login_state user user-2 "Display Two" team-2 "Team Two" "$2"
    ' bash "${login_script}" "${response}"
    assert_equals "team-2" "$(<"${state_dir}/team-id.txt")" "${profile} atomic replacement"
}

test_wallpaper() {
    local output="${tmp_dir}/wallpaper.svg"

    python3 "${WALLPAPER}" 'Cóndor <&> "Rojo"' "bo.19" "${output}"
    assert_contains "${output}" "Cóndor &lt;&amp;&gt; &quot;Rojo&quot;"
    assert_contains "${output}" "Equipo: bo.19"
    python3 - "${output}" <<'PY'
import sys
import xml.etree.ElementTree as ET

ET.parse(sys.argv[1])
PY
}

test_stats_observability() {
    local state_dir="${tmp_dir}/stats-state"
    local payload="${tmp_dir}/stats-payload.json"

    mkdir -p "${state_dir}"
    printf 'user\n' > "${state_dir}/username.txt"
    printf 'user-17\n' > "${state_dir}/user-id.txt"
    printf 'bo-17\n' > "${state_dir}/team-id.txt"
    printf 'Altiplano\n' > "${state_dir}/team-name.txt"
    printf '[]\n' > "${tmp_dir}/logs.json"
    printf '{}\n' > "${tmp_dir}/metrics.json"
    printf '{}\n' > "${tmp_dir}/hardware.json"

    python3 "${STATS_PAYLOAD}" machine-1 "${tmp_dir}/logs.json" \
        "${tmp_dir}/metrics.json" "${tmp_dir}/hardware.json" "${state_dir}" > "${payload}"
    python3 - "${payload}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    payload = json.load(fh)
login = payload["data"]["login"]
assert payload["machine_id"] == "machine-1"
assert login["team_id"] == "bo-17"
assert login["team_name"] == "Altiplano"
PY
}

test_parser
test_atomic_persistence "${GNOME_LOGIN}" gnome
test_atomic_persistence "${XFCE_LOGIN}" xfce
test_wallpaper
test_stats_observability

echo "PASS: team identity is validated, persisted, displayed, and observable."
