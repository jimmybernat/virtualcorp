#!/bin/sh

set -eu

TARGET="/target"
SSH_DIR="${TARGET}/home/sysadmin/.ssh"
AUTHORIZED_KEYS="${SSH_DIR}/authorized_keys"

mkdir -p "${SSH_DIR}"

cat > "${AUTHORIZED_KEYS}" <<'EOF_KEYS'
__AUDITOR_PUBLIC_KEY__
__SYSADMIN_PUBLIC_KEY__
EOF_KEYS

chmod 700 "${SSH_DIR}"
chmod 600 "${AUTHORIZED_KEYS}"
in-target chown -R sysadmin:sysadmin /home/sysadmin/.ssh

mkdir -p "${TARGET}/etc/sudoers.d"

cat > "${TARGET}/etc/sudoers.d/sysadmin" <<'EOF_SUDO'
sysadmin ALL=(ALL:ALL) NOPASSWD: ALL
EOF_SUDO

chmod 440 "${TARGET}/etc/sudoers.d/sysadmin"
in-target passwd -l sysadmin

cat > "${TARGET}/etc/default/keyboard" <<'EOF_KEYBOARD'
XKBMODEL="pc105"
XKBLAYOUT="es"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF_KEYBOARD

if [ -d "${TARGET}/etc/X11" ]; then
    mkdir -p "${TARGET}/etc/X11/xorg.conf.d"

    cat > "${TARGET}/etc/X11/xorg.conf.d/00-keyboard.conf" <<'EOF_XORG_KEYBOARD'
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbModel" "pc105"
    Option "XkbLayout" "es"
EndSection
EOF_XORG_KEYBOARD
fi

in-target systemctl enable ssh
