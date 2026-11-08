#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/common.sh"
SERVER_TEMPLATE_NAME="${DEBIAN_SERVER_TEMPLATE_NAME:-debian-server-template}"
DESKTOP_TEMPLATE_NAME="${DEBIAN_DESKTOP_TEMPLATE_NAME:-debian-desktop-template}"

SERVER_MEMORY_MB="${DEBIAN_SERVER_MEMORY_MB:-2048}"
DESKTOP_MEMORY_MB="${DEBIAN_DESKTOP_MEMORY_MB:-3072}"
TEMPLATE_CPUS="${DEBIAN_TEMPLATE_CPUS:-2}"
TEMPLATE_DISK_MB="${DEBIAN_TEMPLATE_DISK_MB:-32768}"

SERVER_SSH_PORT=2223
DESKTOP_SSH_PORT=2224

PRESEED_DIR="${CONFIGS_DIR}/preseed"
SERVER_PRESEED="${PRESEED_DIR}/debian-server.cfg"
DESKTOP_PRESEED="${PRESEED_DIR}/debian-desktop.cfg"
POSTINSTALL_TEMPLATE="${PRESEED_DIR}/debian-postinstall.sh"

BUILD_DIR="${ARTIFACTS_DIR}/build/templates"
VM_BASE_DIR="${ARTIFACTS_DIR}/vms/templates"
check_requirements() {
    log_info "Comprobando requisitos para crear los templates..."

    local command_name

    for command_name in curl sha256sum ssh ssh-keyscan openssl; do
        if ! command -v "${command_name}" >/dev/null 2>&1; then
            log_err "No se encuentra el comando requerido: ${command_name}"
            return 1
        fi
    done

    if [[ -z "${DEBIAN_ISO_URL:-}" ||
          -z "${DEBIAN_ISO_PATH:-}" ||
          -z "${DEBIAN_ISO_SHA256:-}" ]]; then
        log_err "Faltan variables de configuración de la ISO de Debian"
        return 1
    fi

    local required_file

    for required_file in \
        "${SERVER_PRESEED}" \
        "${DESKTOP_PRESEED}" \
        "${POSTINSTALL_TEMPLATE}" \
        "${AUDIT_PUB_KEY_FILE}" \
        "${SYSADMIN_PUB_KEY_FILE}" \
        "${SYSADMIN_PRIVATE_KEY_FILE}"; do

        if [[ ! -f "${required_file}" ]]; then
            log_err "No se encuentra el archivo requerido: ${required_file}"
            return 1
        fi
    done

    log_ok "Requisitos comprobados correctamente"
}
download_debian_iso() {
    local partial_file="${DEBIAN_ISO_PATH}.part"
    local actual_sha256

    mkdir -p "$(dirname "${DEBIAN_ISO_PATH}")"

    if [[ -f "${DEBIAN_ISO_PATH}" ]]; then
        actual_sha256="$(sha256sum "${DEBIAN_ISO_PATH}")"
        actual_sha256="${actual_sha256%% *}"

        if [[ "${actual_sha256}" == "${DEBIAN_ISO_SHA256}" ]]; then
            log_ok "La ISO de Debian ya existe y su SHA256 es correcto"
            return 0
        fi

        log_warn "La ISO existente no tiene el SHA256 esperado; se descargará otra vez"
    fi

    log_info "Descargando ${DEBIAN_ISO_FILENAME}..."

    curl \
        --fail \
        --location \
        --retry 3 \
        --continue-at - \
        --output "${partial_file}" \
        "${DEBIAN_ISO_URL}"

    actual_sha256="$(sha256sum "${partial_file}")"
    actual_sha256="${actual_sha256%% *}"

    if [[ "${actual_sha256}" != "${DEBIAN_ISO_SHA256}" ]]; then
        log_err "La suma SHA256 de la ISO descargada no es correcta"
        rm -f "${partial_file}"
        return 1
    fi

    mv "${partial_file}" "${DEBIAN_ISO_PATH}"
    log_ok "ISO de Debian descargada y verificada correctamente"
}
render_postinstall() {
    local rendered_postinstall="${BUILD_DIR}/debian-postinstall.sh"
    local auditor_public_key
    local sysadmin_public_key
    local line

    mkdir -p "${BUILD_DIR}"

    auditor_public_key="$(<"${AUDIT_PUB_KEY_FILE}")"
    sysadmin_public_key="$(<"${SYSADMIN_PUB_KEY_FILE}")"

    : > "${rendered_postinstall}"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            "__AUDITOR_PUBLIC_KEY__")
                printf '%s\n' "${auditor_public_key}" >> "${rendered_postinstall}"
                ;;
            "__SYSADMIN_PUBLIC_KEY__")
                printf '%s\n' "${sysadmin_public_key}" >> "${rendered_postinstall}"
                ;;
            *)
                printf '%s\n' "${line}" >> "${rendered_postinstall}"
                ;;
        esac
    done < "${POSTINSTALL_TEMPLATE}"

    chmod +x "${rendered_postinstall}"

    local rendered_content
    rendered_content="$(<"${rendered_postinstall}")"

    if [[ "${rendered_content}" == *"__AUDITOR_PUBLIC_KEY__"* ||
          "${rendered_content}" == *"__SYSADMIN_PUBLIC_KEY__"* ]]; then
        log_err "No se han sustituido correctamente las claves SSH"
        return 1
    fi

    RENDERED_POSTINSTALL="${rendered_postinstall}"
    log_ok "Postinstalador generado con las claves públicas SSH"
}
check_requirements
download_debian_iso
render_postinstall
