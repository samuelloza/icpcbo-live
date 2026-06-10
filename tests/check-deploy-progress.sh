#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
. "${PROJECT_DIR}/overlay/usr/lib/contest/lib/progress.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

source_file="${tmp_dir}/filesystem.squashfs"
destination_file="${tmp_dir}/copied.squashfs"
progress_log="${tmp_dir}/progress.log"

dd if=/dev/zero of="${source_file}" bs=1M count=8 status=none
COPY_PROGRESS_INTERVAL=0.01 \
    copy_file_with_progress \
        "${source_file}" \
        "${destination_file}" \
        "filesystem.squashfs" 2> "${progress_log}"

cmp "${source_file}" "${destination_file}"
grep -q '\[##############################\] 100% filesystem.squashfs' "${progress_log}"

echo "PASS: deployment copies files with byte-based progress."
