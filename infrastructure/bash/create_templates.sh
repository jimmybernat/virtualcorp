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
TEMPLATE_PASSWORD_FILE="${BUILD_DIR}/sysadmin-password"
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
create_template_vm() {
    local vm_name="$1"
    local memory_mb="$2"
    local video_memory_mb="$3"
    local ssh_port="$4"
    local disk_path="${VM_BASE_DIR}/${vm_name}/${vm_name}.vdi"

    if "${VBOXMANAGE_BIN}" showvminfo "${vm_name}" >/dev/null 2>&1; then
        log_warn "La máquina ${vm_name} ya existe; no se vuelve a crear"
        return 0
    fi

    log_info "Creando la máquina virtual ${vm_name}..."

    mkdir -p "${VM_BASE_DIR}"

    "${VBOXMANAGE_BIN}" createvm \
        --name "${vm_name}" \
        --ostype "Debian_64" \
        --groups "${VM_TEMPLATES_GROUP}" \
        --basefolder "${VM_BASE_DIR}" \
        --register

    "${VBOXMANAGE_BIN}" modifyvm "${vm_name}" \
        --memory "${memory_mb}" \
        --cpus "${TEMPLATE_CPUS}" \
        --vram "${video_memory_mb}" \
        --graphicscontroller "vmsvga" \
        --boot1 dvd \
        --boot2 disk \
        --boot3 none \
        --boot4 none \
        --nic1 nat \
        --natpf1 "ssh,tcp,127.0.0.1,${ssh_port},,22"

    "${VBOXMANAGE_BIN}" createmedium disk \
        --filename "${disk_path}" \
        --size "${TEMPLATE_DISK_MB}" \
        --format VDI \
        --variant Standard

    "${VBOXMANAGE_BIN}" storagectl "${vm_name}" \
        --name "SATA Controller" \
        --add sata \
        --controller IntelAhci \
        --portcount 4 \
        --bootable on

    "${VBOXMANAGE_BIN}" storageattach "${vm_name}" \
        --storagectl "SATA Controller" \
        --port 0 \
        --device 0 \
        --type hdd \
        --medium "${disk_path}"

    log_ok "Máquina ${vm_name} creada correctamente"
}
prepare_password_file() {
    mkdir -p "${BUILD_DIR}"

    if [[ -s "${TEMPLATE_PASSWORD_FILE}" ]]; then
        chmod 600 "${TEMPLATE_PASSWORD_FILE}"
        log_ok "El archivo de contraseña temporal ya existe"
        return 0
    fi

    log_info "Generando una contraseña temporal para sysadmin..."

    (
        umask 077
        openssl rand -base64 24 > "${TEMPLATE_PASSWORD_FILE}"
    )

    log_ok "Contraseña temporal generada fuera del repositorio"
}
install_template() {
    local vm_name="$1"
    local preseed_file="$2"
    local install_marker="${BUILD_DIR}/${vm_name}.install-started"
    local auxiliary_path="${BUILD_DIR}/${vm_name}"

    if [[ -f "${install_marker}" ]]; then
        log_warn "La instalación de ${vm_name} ya fue iniciada"
        return 0
    fi

    if [[ ! -f "${preseed_file}" ]]; then
        log_err "No se encuentra el preseed: ${preseed_file}"
        return 1
    fi

    mkdir -p "${auxiliary_path}"

    log_info "Preparando la instalación desatendida de ${vm_name}..."

    "${VBOXMANAGE_BIN}" unattended install "${vm_name}" \
        --iso="${DEBIAN_ISO_PATH}" \
        --user="sysadmin" \
        --user-password-file="${TEMPLATE_PASSWORD_FILE}" \
        --full-user-name="VirtualCorp Sysadmin" \
        --locale="es_ES" \
        --language="es" \
        --country="ES" \
        --time-zone="Europe/Madrid" \
        --hostname="${vm_name}.virtualcorp.local" \
        --package-selection-adjustment="minimal" \
        --script-template="${preseed_file}" \
        --post-install-template="${RENDERED_POSTINSTALL}" \
        --auxiliary-base-path="${auxiliary_path}" \
        --start-vm="headless" 2>&1 | \
        sed -E \
            -e 's/^([[:space:]]*password[[:space:]]*=).*/\1 [OCULTA]/' \
            -e 's/^([[:space:]]*user-password[[:space:]]*=).*/\1 [OCULTA]/'\
	    -e 's/^([[:space:]]*admin-password[[:space:]]*=).*/\1 [OCULTA]/'
    touch "${install_marker}"
    log_ok "Instalación desatendida de ${vm_name} iniciada"
}
wait_for_template_ssh() {
    local vm_name="$1"
    local ssh_port="$2"
    local timeout_seconds="${DEBIAN_TEMPLATE_INSTALL_TIMEOUT:-2400}"
    local elapsed=0

    log_info "Esperando a que termine la instalación de ${vm_name}..."

    while (( elapsed < timeout_seconds )); do
        if ssh \
            -p "${ssh_port}" \
            -i "${SYSADMIN_PRIVATE_KEY_FILE}" \
            -o BatchMode=yes \
            -o ConnectTimeout=5 \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            sysadmin@127.0.0.1 true >/dev/null 2>&1; then

            log_ok "SSH disponible en ${vm_name}"
            return 0
        fi

        sleep 15
        elapsed=$((elapsed + 15))
    done

    log_err "Tiempo agotado esperando a ${vm_name}"
    return 1
}
wait_for_template_poweroff() {
    local vm_name="$1"
    local timeout_seconds=180
    local elapsed=0
    local vm_state

    log_info "Esperando a que ${vm_name} se apague..."

    while (( elapsed < timeout_seconds )); do
        vm_state="$(
            "${VBOXMANAGE_BIN}" showvminfo "${vm_name}" --machinereadable |
                sed -n 's/^VMState="\([^"]*\)"/\1/p'
        )"

        if [[ "${vm_state}" == "poweroff" ]]; then
            log_ok "${vm_name} está apagada"
            return 0
        fi

        sleep 5
        elapsed=$((elapsed + 5))
    done

    log_err "Tiempo agotado esperando el apagado de ${vm_name}"
    return 1
}
finalize_template() {
    local vm_name="$1"
    local ssh_port="$2"
    local snapshot_description="$3"

    if "${VBOXMANAGE_BIN}" snapshot "${vm_name}" list --machinereadable 2>/dev/null |
        grep -qE '^SnapshotName(-[0-9]+)?="base-clean"$'; then

        log_ok "${vm_name} ya está finalizada y tiene la instantánea base-clean"
        return 0
    fi

    wait_for_template_ssh "${vm_name}" "${ssh_port}"

    log_info "Sellando la plantilla ${vm_name}..."

    ssh \
        -p "${ssh_port}" \
        -i "${SYSADMIN_PRIVATE_KEY_FILE}" \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        sysadmin@127.0.0.1 \
        'sudo rm -f /etc/ssh/ssh_host_* /var/lib/dbus/machine-id /var/lib/systemd/random-seed /var/lib/dhcp/dhclient*.leases; printf "uninitialized\n" | sudo tee /etc/machine-id >/dev/null; sudo sync; sudo poweroff' \
        || true

    wait_for_template_poweroff "${vm_name}"

    "${VBOXMANAGE_BIN}" modifyvm "${vm_name}" --nic1 none

    "${VBOXMANAGE_BIN}" snapshot "${vm_name}" take "base-clean" \
        --description "${snapshot_description}"

    log_ok "Plantilla ${vm_name} sellada y preparada para clones enlazados"
}
check_requirements
download_debian_iso
render_postinstall
prepare_password_file

create_template_vm \
    "${SERVER_TEMPLATE_NAME}" \
    "${SERVER_MEMORY_MB}" \
    16 \
    "${SERVER_SSH_PORT}"

create_template_vm \
    "${DESKTOP_TEMPLATE_NAME}" \
    "${DESKTOP_MEMORY_MB}" \
    128 \
    "${DESKTOP_SSH_PORT}"

install_template \
    "${SERVER_TEMPLATE_NAME}" \
    "${SERVER_PRESEED}"

install_template \
    "${DESKTOP_TEMPLATE_NAME}" \
    "${DESKTOP_PRESEED}"
finalize_template \
    "${SERVER_TEMPLATE_NAME}" \
    "${SERVER_SSH_PORT}" \
    "Debian Server 13 limpio y sellado"

finalize_template \
    "${DESKTOP_TEMPLATE_NAME}" \
    "${DESKTOP_SSH_PORT}" \
    "Debian Desktop 13 LXQt limpio y sellado"

rm -f "${TEMPLATE_PASSWORD_FILE}"
log_ok "Plantillas Debian creadas y preparadas correctamente"
