#!/usr/bin/env bash
# Corre todos los tests/check-*.sh y resume el resultado.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

pass=0
fail=0
for test in check-*.sh; do
    if output="$(bash "${test}" 2>&1)"; then
        echo "PASS  ${test}"
        pass=$((pass + 1))
    else
        echo "FAIL  ${test}"
        echo "${output}" | tail -6 | sed 's/^/      /'
        fail=$((fail + 1))
    fi
done

echo "---- ${pass} passed, ${fail} failed ----"
[[ "${fail}" -eq 0 ]]
