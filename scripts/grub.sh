#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./build/lib/grub.sh
source "${SCRIPT_DIR}/build/grub.sh"
