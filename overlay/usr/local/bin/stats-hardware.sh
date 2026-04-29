#!/usr/bin/env bash

set -euo pipefail

CPU_MODEL="$(lscpu | awk -F: '/Model name/ {sub(/^[ \t]+/, "", $2); print $2; exit}')"
CPU_COUNT="$(lscpu | awk -F: '/^CPU\(s\)/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')"
MEM_TOTAL_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"

/usr/local/bin/stats-build-hardware.py \
    "${CPU_MODEL}" \
    "${CPU_COUNT}" \
    "${MEM_TOTAL_MB}"
