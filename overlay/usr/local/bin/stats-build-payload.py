#!/usr/bin/env python3

import json
import os
import sys


def read_optional(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read().strip()
    except FileNotFoundError:
        return ""


def main() -> None:
    machine_id = sys.argv[1]
    logs_file = sys.argv[2]
    metrics_file = sys.argv[3]
    hardware_file = sys.argv[4]
    login_state_dir = sys.argv[5]

    with open(logs_file, encoding="utf-8") as fh:
        logs = json.load(fh)

    with open(metrics_file, encoding="utf-8") as fh:
        metrics = json.load(fh)

    with open(hardware_file, encoding="utf-8") as fh:
        hardware = json.load(fh)

    login = {
        "username": read_optional(os.path.join(login_state_dir, "username.txt")),
        "user_id": read_optional(os.path.join(login_state_dir, "user-id.txt")),
    }

    payload = {
        "machine_id": machine_id,
        "data": {
            "login": login,
            "hardware": hardware,
            "metrics": metrics,
            "logs": logs,
        },
    }

    print(json.dumps(payload, ensure_ascii=False))


if __name__ == "__main__":
    main()
