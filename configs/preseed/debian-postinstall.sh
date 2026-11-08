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
in-target systemctl enable ssh
