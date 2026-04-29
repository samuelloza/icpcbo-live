#!/usr/bin/env python3

import json
import sys


def main() -> None:
    payload = {
        "cpu_model": sys.argv[1],
        "cpu_count": int(sys.argv[2]),
        "mem_total_mb": int(sys.argv[3]),
    }

    print(json.dumps(payload, ensure_ascii=False))


if __name__ == "__main__":
    main()
