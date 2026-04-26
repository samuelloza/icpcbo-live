#!/usr/bin/env bash
# Run all regular files in a directory as bash hooks, sorted by filename.
# Usage: run-hook-dir.sh <directory>
#
# This script is copied into the chroot during the build and sourced by
# both phase_install_and_customize and phase_trim. Extracting it here
# eliminates the duplicate inline function definitions in build.sh.

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: run-hook-dir.sh <directory>" >&2
    exit 1
fi

dir="$1"

[ -d "${dir}" ] || exit 0

while IFS= read -r hook; do
    [ -f "${hook}" ] || continue
    echo "I: running hook ${hook}" >&2
    /bin/bash -eux "${hook}"
done < <(find "${dir}" -maxdepth 1 -type f | sort)
