#!/usr/bin/env bash

set -euo pipefail

FIREFOX_DIR="/usr/lib/firefox-esr"
DEFAULT_BROWSER_URL_VAL="${DEFAULT_BROWSER_URL:-file:///usr/share/doc/icpcbo/index.html}"

if [ ! -d "${FIREFOX_DIR}" ]; then
    echo "W: firefox-esr not found at ${FIREFOX_DIR}, skipping Firefox defaults" >&2
    exit 0
fi

mkdir -p "${FIREFOX_DIR}/defaults/pref"

# Enable autoconfig
cat > "${FIREFOX_DIR}/defaults/pref/icpcbo-autoconfig.js" <<'EOF'
pref("general.config.filename", "icpcbo.cfg");
pref("general.config.obscure_value", 0);
EOF

# Autoconfig preferences (first non-comment line is skipped by Firefox — start with comment)
cat > "${FIREFOX_DIR}/icpcbo.cfg" <<EOF
// Default homepage: local contest documentation
defaultPref("browser.startup.homepage", "${DEFAULT_BROWSER_URL_VAL}");
defaultPref("browser.startup.page", 1);

// Disable telemetry and reporting
defaultPref("datareporting.healthreport.uploadEnabled", false);
defaultPref("datareporting.policy.dataSubmissionEnabled", false);
defaultPref("toolkit.telemetry.enabled", false);
defaultPref("toolkit.telemetry.server", "");
defaultPref("toolkit.telemetry.unified", false);

// Disable automatic updates
defaultPref("app.update.auto", false);
defaultPref("app.update.enabled", false);

// Suppress post-update and welcome tabs
defaultPref("browser.startup.homepage_override.mstone", "ignore");
defaultPref("startup.homepage_welcome_url", "");
defaultPref("startup.homepage_welcome_url.additional", "");

// Disable password manager
defaultPref("signon.rememberSignons", false);
EOF
