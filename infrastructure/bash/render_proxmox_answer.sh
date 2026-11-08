#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TEMPLATE="${CONFIGS_DIR}/proxmox/answer.toml.in"
BUILD_DIR="${ARTIFACTS_DIR}/build/proxmox"
ANSWER="${BUILD_DIR}/answer.toml"
PASSWORD="${BUILD_DIR}/root-password"

for file in "${TEMPLATE}" "${AUDIT_PUB_KEY_FILE}" "${SYSADMIN_PUB_KEY_FILE}"; do
    [[ -f "${file}" ]] || { log_err "Falta el archivo: ${file}"; exit 1; }
done

mkdir -p "${BUILD_DIR}"
chmod 700 "${BUILD_DIR}"

if [[ ! -f "${PASSWORD}" ]]; then
    openssl rand -base64 24 > "${PASSWORD}"
    chmod 600 "${PASSWORD}"
fi

password_hash="$(openssl passwd -6 "$(cat "${PASSWORD}")")"
auditor_key="$(tr -d '\r\n' < "${AUDIT_PUB_KEY_FILE}")"
sysadmin_key="$(tr -d '\r\n' < "${SYSADMIN_PUB_KEY_FILE}")"

content="$(cat "${TEMPLATE}")"
content="${content//__ROOT_PASSWORD_HASH__/${password_hash}}"
content="${content//__AUDITOR_PUBLIC_KEY__/${auditor_key}}"
content="${content//__SYSADMIN_PUBLIC_KEY__/${sysadmin_key}}"

printf '%s\n' "${content}" > "${ANSWER}"
chmod 600 "${ANSWER}"

grep -q '__[A-Z_]*__' "${ANSWER}" && {
    log_err "Quedan marcadores sin sustituir"
    exit 1
}

log_ok "Archivo de respuestas de Proxmox generado correctamente"
