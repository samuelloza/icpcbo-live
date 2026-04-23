#!/usr/bin/env bash

set -euo pipefail
exit 0
DEFAULT_USER_VAL="${DEFAULT_USER:-icpc}"
CACHE_DIR="/tmp/cache/contestant-vm-vsix"

VSCODE_CPPT_VERSION="1.24.5"
VSCODE_VIM_VERSION="1.29.0"
VSCODE_CLANGD_VERSION="0.1.33"
VSCODE_INTELLIJ_VERSION="1.7.3"
# Java extension version includes a build number (e.g. 1.42.0-561).
# Update both variables together when bumping the release.
VSCODE_JAVA_VERSION="1.42.0"
VSCODE_JAVA_BUILD="561"

download_vsix() {
    local url="$1"
    local dst="$2"
    if ! /tmp/cached-curl.sh "$url" "$dst"; then
        echo "W: failed downloading VSIX: $url" >&2
        return 1
    fi
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
download_vsix "https://github.com/clangd/vscode-clangd/releases/download/${VSCODE_CLANGD_VERSION}/vscode-clangd-${VSCODE_CLANGD_VERSION}.vsix" "${CACHE_DIR}/clangd.vsix" || true
download_vsix "https://github.com/redhat-developer/vscode-java/releases/download/v${VSCODE_JAVA_VERSION}/vscode-java-${VSCODE_JAVA_VERSION}-${VSCODE_JAVA_BUILD}.vsix" "${CACHE_DIR}/java.vsix" || true

chown -R "${DEFAULT_USER_VAL}:${DEFAULT_USER_VAL}" "${CACHE_DIR}"

while IFS= read -r ext; do
    [ -f "${ext}" ] || continue
    runuser -u "${DEFAULT_USER_VAL}" -- env HOME="${user_home}" code --install-extension "${ext}" || true
done < <(find "${CACHE_DIR}" -maxdepth 1 -type f -name '*.vsix' | sort)
