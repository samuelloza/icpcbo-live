#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local label="$3"

    if [[ "${actual}" != "${expected}" ]]; then
        printf 'Expected %s:\n%s\n' "${label}" "${expected}" >&2
        printf 'Actual %s:\n%s\n' "${label}" "${actual}" >&2
        fail "${label} does not match expected content"
    fi
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

# shellcheck source=/dev/null
source "${PROJECT_DIR}/start.sh"

OUTPUT_DIR="${tmp_dir}/output"
mkdir -p "${OUTPUT_DIR}"
touch "${OUTPUT_DIR}/older.iso"
sleep 1
touch "${OUTPUT_DIR}/latest.iso"
touch "${OUTPUT_DIR}/${ISO_NAME}-grub-preview.iso"

assert_equals "${OUTPUT_DIR}" "$(resolve_output_dir)" "resolve_output_dir writable dir"
assert_equals "${OUTPUT_DIR}/latest.iso" "$(latest_iso_path "${OUTPUT_DIR}")" "latest_iso_path newest file"
assert_equals "${OUTPUT_DIR}/${ISO_NAME}-grub-preview.iso" "$(preview_iso_path "${OUTPUT_DIR}")" "preview_iso_path"

preview_dir="${tmp_dir}/preview/grub-preview"
mkdir -p "${preview_dir}/boot/grub" "${preview_dir}/${CONTEST_DIR}"
cat > "${preview_dir}/boot/grub/grub.cfg" <<'EOF'
set default=0
EOF
cat > "${preview_dir}/${CONTEST_DIR}/grub-entry.cfg" <<'EOF'
menuentry "preview" {}
EOF

preview_output="$(show_grub_preview "${tmp_dir}/preview")"

case "${preview_output}" in
    *"${preview_dir}/boot/grub/grub.cfg"* ) ;;
    * ) fail "show_grub_preview did not print grub.cfg path" ;;
esac

case "${preview_output}" in
    *"${preview_dir}/${CONTEST_DIR}/grub-entry.cfg"* ) ;;
    * ) fail "show_grub_preview did not print grub-entry.cfg path" ;;
esac

action_log="${tmp_dir}/start-actions.log"

build_target() { echo "build:$1" >> "${action_log}"; }
launch_vm() { echo "launch:$1" >> "${action_log}"; }
launch_winxp() { echo "winxp:$1:$2" >> "${action_log}"; }
show_grub_preview() { echo "show:$1" >> "${action_log}"; }
start_interactive_menu() { echo "menu" >> "${action_log}"; }
start_usage() { echo "help" >> "${action_log}"; }

latest_iso_path() { echo "/tmp/any.iso"; }
preview_iso_path() { echo "/tmp/preview.iso"; }
require_iso() { echo "require:$1" >> "${action_log}"; }
ISO_PATH=""

run_start_action run
run_start_action build
run_start_action build-run
run_start_action build-preview
run_start_action grub-preview
run_start_action menu
run_start_action help

assert_equals "$(cat <<EOF
require:/tmp/any.iso
winxp:1:/tmp/any.iso
build:full
build:full
require:/tmp/any.iso
winxp:1:/tmp/any.iso
build:grub-preview
require:/tmp/preview.iso
launch:/tmp/preview.iso
show:${OUTPUT_DIR_RESOLVED}
menu
help
EOF
)" "$(cat "${action_log}")" "run_start_action dispatch"

echo "PASS: start.sh resolves paths and dispatches start actions correctly."
