#!/usr/bin/env bash

set -euo pipefail

DEFAULT_USER_VAL="${DEFAULT_USER}"
CACHE_DIR="/tmp/cache/contestants-vsix"

VSCODE_CPPT_VERSION="1.24.5"
VSCODE_VIM_VERSION="1.32.4"
#VSCODE_CLANGD_VERSION="0.4.0"
VSCODE_INTELLIJ_VERSION="1.7.7"
# La extensión de Java incluye un número de build
# (por ejemplo 1.42.0-561).
VSCODE_JAVA_VERSION="1.54.0"
VSCODE_JAVA_BUILD="561"
KOTLIN_LSP_API_URL="https://api.github.com/repos/Kotlin/kotlin-lsp/releases/latest"

download_vsix() {
    local url="$1"
    local dst="$2"
    if ! /tmp/cached-curl.sh "$url" "$dst"; then
        echo "W: failed downloading VSIX: $url" >&2
        return 1
    fi
}

download_kotlin_lsp_vsix() {
    local api_json="${CACHE_DIR}/kotlin-lsp-release.json"
    local asset_url

    if ! /tmp/cached-curl.sh "${KOTLIN_LSP_API_URL}" "${api_json}"; then
        echo "W: failed downloading Kotlin LSP release metadata" >&2
        return 1
    fi

    asset_url="$(
        python3 - "${api_json}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)

for asset in data.get("assets", []):
    name = asset.get("name", "")
    if name.endswith(".vsix"):
        print(asset.get("browser_download_url", ""))
        break
PY
    )"

    if [ -z "${asset_url}" ]; then
        echo "W: Kotlin LSP release metadata did not contain a VSIX asset" >&2
        return 1
    fi

    download_vsix "${asset_url}" "${CACHE_DIR}/kotlin-lsp.vsix"
}

if ! command -v code >/dev/null 2>&1; then
    echo "W: VSCode not found, skipping extensions" >&2
    exit 0
fi

if ! id -u "${DEFAULT_USER_VAL}" >/dev/null 2>&1; then
    echo "W: user ${DEFAULT_USER_VAL} not found, skipping extensions" >&2
    exit 0
fi

user_home="$(getent passwd "${DEFAULT_USER_VAL}" | cut -d: -f6)"
mkdir -p "${CACHE_DIR}"

download_vsix "https://github.com/microsoft/vscode-cpptools/releases/download/v${VSCODE_CPPT_VERSION}/cpptools-linux-x64.vsix" "${CACHE_DIR}/cpptools.vsix" || true
download_vsix "https://github.com/VSCodeVim/Vim/releases/download/v${VSCODE_VIM_VERSION}/vim-${VSCODE_VIM_VERSION}.vsix" "${CACHE_DIR}/vim.vsix" || true
download_vsix "https://github.com/kasecato/vscode-intellij-idea-keybindings/releases/download/v${VSCODE_INTELLIJ_VERSION}/intellij-idea-keybindings-${VSCODE_INTELLIJ_VERSION}.vsix" "${CACHE_DIR}/intellij.vsix" || true
#download_vsix "https://github.com/clangd/vscode-clangd/releases/download/${VSCODE_CLANGD_VERSION}/vscode-clangd-${VSCODE_CLANGD_VERSION}.vsix" "${CACHE_DIR}/clangd.vsix" || true
download_vsix "https://github.com/redhat-developer/vscode-java/releases/download/v${VSCODE_JAVA_VERSION}/vscode-java-${VSCODE_JAVA_VERSION}-${VSCODE_JAVA_BUILD}.vsix" "${CACHE_DIR}/java.vsix" || true
download_kotlin_lsp_vsix || true

chown -R "${DEFAULT_USER_VAL}:${DEFAULT_USER_VAL}" "${CACHE_DIR}"

while IFS= read -r ext; do
    [ -f "${ext}" ] || continue
    runuser -u "${DEFAULT_USER_VAL}" -- env HOME="${user_home}" code --install-extension "${ext}" || true
done < <(find "${CACHE_DIR}" -maxdepth 1 -type f -name '*.vsix' | sort)
