#!/usr/bin/env bash
exit
set -euo pipefail

if command -v pip >/dev/null 2>&1; then
    pip install PySide6-Essentials --break-system-packages || true
fi
