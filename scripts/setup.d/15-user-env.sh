#!/usr/bin/env bash

set -euo pipefail

DEFAULT_USER_VAL="${DEFAULT_USER:-icpc}"
OPT_DIR="${OPT_CONTEST_DIR:-/opt/icpc}"

# ----------------------------------------------------------------
# /etc/skel setup — applied to user home by build.sh after hooks
# ----------------------------------------------------------------

mkdir -p /etc/skel/.config

# Skip GNOME initial setup wizard for new users
echo yes > /etc/skel/.config/gnome-initial-setup-done

# VSCode default settings
mkdir -p /etc/skel/.config/Code/User
cat > /etc/skel/.config/Code/User/settings.json <<'EOM'
{
    "C_Cpp.default.cppStandard": "gnu++17",
    "editor.fontSize": 14,
    "editor.tabSize": 4,
    "editor.insertSpaces": true,
    "terminal.integrated.fontSize": 13
}
EOM

# Desktop shortcuts
mkdir -p /etc/skel/Desktop
if [ -f "${OPT_DIR}/misc/icpcbo.desktop" ]; then
    cp "${OPT_DIR}/misc/icpcbo.desktop" /etc/skel/Desktop/
    chmod +x /etc/skel/Desktop/icpcbo.desktop
fi
if [ -f /usr/share/applications/gnome-keyboard-panel.desktop ]; then
    cp /usr/share/applications/gnome-keyboard-panel.desktop /etc/skel/Desktop/
    chmod +x /etc/skel/Desktop/gnome-keyboard-panel.desktop
fi

# Add contest tools to PATH and set aliases
cat >> /etc/skel/.bashrc <<EOF

# ICPC Bolivia contest tools
export PATH="\${PATH}:${OPT_DIR}/bin"
alias icpcboconf='sudo ${OPT_DIR}/bin/icpcboconf.sh'
alias icpcbobackup='sudo ${OPT_DIR}/bin/icpcbobackup.sh'
EOF

# Set timezone from contest config at login
cat >> /etc/skel/.profile <<EOF

# ICPC Bolivia: apply contest timezone if configured
_tz_file="${OPT_DIR}/config/timezone"
if [ -f "\${_tz_file}" ]; then
    TZ=\$(cat "\${_tz_file}")
    export TZ
fi
unset _tz_file
EOF

# ----------------------------------------------------------------
# System-wide PATH for all users
# ----------------------------------------------------------------
cat > /etc/profile.d/icpc.sh <<EOF
export PATH="\${PATH}:${OPT_DIR}/bin"
EOF

# ----------------------------------------------------------------
# GNOME autostart entry
# ----------------------------------------------------------------
if [ -f "${OPT_DIR}/misc/icpcbostart.desktop" ]; then
    mkdir -p /usr/share/gnome/autostart
    cp "${OPT_DIR}/misc/icpcbostart.desktop" /usr/share/gnome/autostart/
fi

# ----------------------------------------------------------------
# Sudoers: allow contestant user to run contest tools as root
# ----------------------------------------------------------------
cat > /etc/sudoers.d/contestant-vm <<SUDO
${DEFAULT_USER_VAL} ALL=(root) NOPASSWD: ${OPT_DIR}/bin/icpcboconf.sh
${DEFAULT_USER_VAL} ALL=(root) NOPASSWD: ${OPT_DIR}/bin/icpcbobackup.sh
${DEFAULT_USER_VAL} ALL=(root) NOPASSWD: ${OPT_DIR}/sbin/contest.sh
SUDO
chmod 440 /etc/sudoers.d/contestant-vm

# ----------------------------------------------------------------
# Apply directly to the user that already exists in the chroot
# (build.sh will later also copy skel, overwriting these files —
#  writing here ensures correctness even if skel logic changes)
# ----------------------------------------------------------------
if id -u "${DEFAULT_USER_VAL}" >/dev/null 2>&1; then
    user_home="$(getent passwd "${DEFAULT_USER_VAL}" | cut -d: -f6)"

    mkdir -p "${user_home}/.config/Code/User"
    cp /etc/skel/.config/Code/User/settings.json "${user_home}/.config/Code/User/"

    mkdir -p "${user_home}/Desktop"
    [ -f "${OPT_DIR}/misc/icpcbo.desktop" ] && \
        cp "${OPT_DIR}/misc/icpcbo.desktop" "${user_home}/Desktop/" && \
        chmod +x "${user_home}/Desktop/icpcbo.desktop"
    [ -f /usr/share/applications/gnome-keyboard-panel.desktop ] && \
        cp /usr/share/applications/gnome-keyboard-panel.desktop "${user_home}/Desktop/" && \
        chmod +x "${user_home}/Desktop/gnome-keyboard-panel.desktop"

    chown -R "${DEFAULT_USER_VAL}:${DEFAULT_USER_VAL}" \
        "${user_home}/.config" "${user_home}/Desktop" 2>/dev/null || true
fi
