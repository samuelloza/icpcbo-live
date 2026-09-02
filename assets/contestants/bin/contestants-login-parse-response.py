#!/usr/bin/env python3

import json
import re
import shlex
import sys

TEAM_ID_RE = re.compile(r"^(?!.*\.\.)[A-Za-z0-9._-]{1,64}$")


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


if __name__ == "__main__":
    main()
