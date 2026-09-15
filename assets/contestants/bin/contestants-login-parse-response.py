#!/usr/bin/env python3

import json
import re
import shlex
import sys

TEAM_ID_RE = re.compile(r"^(?!.*\.\.)[A-Za-z0-9._-]{1,64}$")
HOMEPAGE_RE = re.compile(r"^https?://[^\s]+$")


def first_value(data: dict, *keys: str) -> object | None:
    for key in keys:
        value = data.get(key)
        if value is not None and value != "":
            return value
    return None


def response_succeeded(data: dict) -> bool:
    value = data.get("ok", data.get("valid"))
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return value == 1
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "ok", "success", "valid"}
    return str(data.get("status", "")).strip().lower() in {
        "ok",
        "success",
        "valid",
    }


def normalize_team(data: dict, required: bool, user_id: str, display_name: str) -> tuple[str, str]:
    team = data.get("team")
    if not isinstance(team, dict):
        team = {}

    team_id_value = first_value(data, "teamId", "team_id")
    if team_id_value is None:
        team_id_value = first_value(team, "id", "teamId", "team_id")

    team_name_value = first_value(data, "teamName", "team_name")
    if team_name_value is None:
        team_name_value = first_value(team, "name", "teamName", "team_name")

    team_id = str(team_id_value or "").strip()
    team_name = str(team_name_value or "").strip()

    if not team_id and not required:
        team_id = user_id
    if not team_name:
        team_name = display_name

    if team_id and not TEAM_ID_RE.fullmatch(team_id):
        raise ValueError("El identificador del equipo recibido no es válido.")
    if team_name and (len(team_name) > 128 or any(ord(char) < 32 for char in team_name)):
        raise ValueError("El nombre del equipo recibido no es válido.")
    if required and not team_id:
        raise ValueError("El servicio no devolvió el identificador obligatorio del equipo.")

    return team_id, team_name


def main() -> None:
    response_file = sys.argv[1]
    http_code = int(sys.argv[2])
    username = sys.argv[3]
    team_id_required = len(sys.argv) < 5 or sys.argv[4].lower() == "true"
    raw = ""

    try:
        with open(response_file, encoding="utf-8") as fh:
            raw = fh.read()
    except FileNotFoundError:
        pass

    ok = False
    message = ""
    user_id = username
    display_name = username
    team_id = ""
    team_name = ""
    region_id = ""
    region_name = ""
    region_enroll_token = ""
    homepage = ""
    logo_url = ""

    if 200 <= http_code < 300:
        try:
            data = json.loads(raw or "{}")
        except json.JSONDecodeError:
            message = "El servicio respondió con un formato JSON inválido."
        else:
            if not isinstance(data, dict):
                message = "El servicio respondió con un objeto JSON inválido."
            else:
                ok = response_succeeded(data)
                message = str(data.get("message") or data.get("detail") or "")
                user_id = str(
                    data.get("userId")
                    or data.get("user_id")
                    or data.get("id")
                    or username
                )
                display_name = str(
                    data.get("displayName")
                    or data.get("display_name")
                    or data.get("name")
                    or username
                )
                if ok:
                    try:
                        team_id, team_name = normalize_team(
                            data, team_id_required, user_id, display_name
                        )
                    except ValueError as exc:
                        ok = False
                        message = str(exc)
                # Sede / región a la que pertenece el usuario. Opcional: si el
                # servicio no la manda, el equipo sigue usando su GROUP_ID horneado.
                region = data.get("region")
                if not isinstance(region, dict):
                    region = {}
                rid = first_value(data, "regionId", "region_id", "sede", "site",
                                  "groupId", "group_id") or first_value(region, "id", "regionId", "region_id")
                rname = first_value(data, "regionName", "region_name") or first_value(region, "name")
                rid = str(rid or "").strip()
                region_id = rid if TEAM_ID_RE.fullmatch(rid) else ""
                region_name = str(rname or "").strip()[:128]
                # Token de enrolamiento de la sede (ISO genérico): el equipo se
                # re-enrola en esa sede. Solo se acepta junto a una region válida.
                rtok = first_value(region, "enrollToken", "enroll_token") \
                    or first_value(data, "regionEnrollToken", "enroll_token")
                region_enroll_token = str(rtok or "").strip()[:200] if region_id else ""
                candidate = str(first_value(data, "homepage", "homePage", "home_page") or "").strip()
                if (HOMEPAGE_RE.fullmatch(candidate)
                        or candidate.startswith("file:///usr/share/doc/contest/")
                        or candidate == "about:blank"):
                    homepage = candidate
                candidate = str(first_value(data, "logoUrl", "logo_url") or "").strip()
                if HOMEPAGE_RE.fullmatch(candidate):
                    logo_url = candidate
    else:
        message = f"El servicio respondió con HTTP {http_code}."

    if not ok and not message:
        message = "Las credenciales no fueron aceptadas."

    print(f"AUTH_OK={shlex.quote('1' if ok else '0')}")
    print(f"AUTH_MESSAGE={shlex.quote(message)}")
    print(f"AUTH_USER_ID={shlex.quote(user_id)}")
    print(f"AUTH_DISPLAY_NAME={shlex.quote(display_name)}")
    print(f"AUTH_TEAM_ID={shlex.quote(team_id)}")
    print(f"AUTH_TEAM_NAME={shlex.quote(team_name)}")
    print(f"AUTH_REGION_ID={shlex.quote(region_id)}")
    print(f"AUTH_REGION_NAME={shlex.quote(region_name)}")
    print(f"AUTH_REGION_ENROLL_TOKEN={shlex.quote(region_enroll_token)}")
    print(f"AUTH_HOMEPAGE={shlex.quote(homepage)}")
    print(f"AUTH_LOGO_URL={shlex.quote(logo_url)}")


if __name__ == "__main__":
    main()
