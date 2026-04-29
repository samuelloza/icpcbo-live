#!/usr/bin/env python3

import json
import sys


def read_text(path: str) -> str:
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def main() -> None:
    payload = {
        "timestamp": sys.argv[1],
        "boot": read_text(sys.argv[2]),
        "system_errors": read_text(sys.argv[3]),
        "kernel_errors": read_text(sys.argv[4]),
    }

    print(json.dumps(payload, ensure_ascii=False))


if __name__ == "__main__":
    main()
