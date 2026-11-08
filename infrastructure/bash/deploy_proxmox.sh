#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

PVE_VM_NAME="${PROXMOX_VM_NAME:-pve01}"
PVE_MEMORY_MB="${PROXMOX_MEMORY_MB:-8192}"
PVE_CPUS="${PROXMOX_CPUS:-4}"
PVE_DISK_MB="${PROXMOX_DISK_MB:-65536}"
PVE_NETWORK="${PROXMOX_NETWORK:-privada}"

PROXMOX_VERSION="${PROXMOX_VERSION:-9.2-1}"
PROXMOX_ISO_FILENAME="${PROXMOX_ISO_FILENAME:-proxmox-ve_${PROXMOX_VERSION}.iso}"
PROXMOX_ISO_URL="${PROXMOX_ISO_URL:-https://enterprise.proxmox.com/iso/${PROXMOX_ISO_FILENAME}}"
PROXMOX_ISO_PATH="${PROXMOX_ISO_PATH:-${ARTIFACTS_DIR}/images/proxmox/${PROXMOX_ISO_FILENAME}}"
PROXMOX_ISO_SHA256="${PROXMOX_ISO_SHA256:-4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c}"

BUILD_DIR="${ARTIFACTS_DIR}/build/proxmox"
ANSWER_TEMPLATE="${CONFIGS_DIR}/proxmox/answer.toml.in"
ANSWER_FILE="${BUILD_DIR}/answer.toml"
AUTO_ISO="${BUILD_DIR}/proxmox-ve_${PROXMOX_VERSION}-auto.iso"
INSTALL_MARKER="${BUILD_DIR}/${PVE_VM_NAME}.install-started"

EQUIPMENT_VM_DIR="${ARTIFACTS_DIR}/vms/equipment"
PVE_VM_DIR="${EQUIPMENT_VM_DIR}/${PVE_VM_NAME}"
PVE_DISK="${PVE_VM_DIR}/${PVE_VM_NAME}.vdi"
PVE_GROUP="${VBOX_ROOT_GROUP:-/VirtualCorp}/Equipment/Servers"

vm_exists() {
    "${VBOXMANAGE_BIN}" showvminfo "$1" >/dev/null 2>&1
}

check_requirements() {
    local command_name

    for command_name in curl sha256sum openssl xorriso proxmox-auto-install-assistant; do
        if ! command -v "${command_name}" >/dev/null 2>&1; then
            log_err "No se encuentra el comando requerido: ${command_name}"
            return 1
        fi
    done

    if [[ ! -x "${SCRIPT_DIR}/render_proxmox_answer.sh" ]]; then
        log_err "Falta el script ${SCRIPT_DIR}/render_proxmox_answer.sh"
        return 1
    fi

    log_ok "Requisitos de Proxmox comprobados correctamente"
}

download_proxmox_iso() {
    local iso_dir
    local temporary_iso

    iso_dir="$(dirname "${PROXMOX_ISO_PATH}")"
    temporary_iso="${PROXMOX_ISO_PATH}.download"
    mkdir -p "${iso_dir}"

    if [[ -f "${PROXMOX_ISO_PATH}" ]]; then
        if printf '%s  %s\n' "${PROXMOX_ISO_SHA256}" "${PROXMOX_ISO_PATH}" |
            sha256sum --check --status; then
            log_ok "La ISO de Proxmox ya existe y su SHA256 es correcto"
            return 0
        fi

        log_err "La ISO existente no coincide con el SHA256 configurado"
        return 1
    fi

    log_info "Descargando ${PROXMOX_ISO_FILENAME}..."
    curl --fail --location --retry 3 \
        --output "${temporary_iso}" \
        "${PROXMOX_ISO_URL}"

    if ! printf '%s  %s\n' "${PROXMOX_ISO_SHA256}" "${temporary_iso}" |
        sha256sum --check --status; then
        rm -f "${temporary_iso}"
        log_err "El SHA256 de la ISO descargada no es correcto"
        return 1
    fi

    mv "${temporary_iso}" "${PROXMOX_ISO_PATH}"
    log_ok "ISO de Proxmox descargada y verificada"
}

render_answer_file() {
    local must_render=false

    if [[ ! -f "${ANSWER_FILE}" ]]; then
        must_render=true
    elif [[ "${ANSWER_TEMPLATE}" -nt "${ANSWER_FILE}" ||
            "${AUDIT_PUB_KEY_FILE}" -nt "${ANSWER_FILE}" ||
            "${SYSADMIN_PUB_KEY_FILE}" -nt "${ANSWER_FILE}" ]]; then
        must_render=true
    fi

    if [[ "${must_render}" == true ]]; then
        "${SCRIPT_DIR}/render_proxmox_answer.sh"
    else
        log_ok "El archivo answer.toml ya está generado"
    fi

    proxmox-auto-install-assistant validate-answer "${ANSWER_FILE}"
    log_ok "Archivo answer.toml validado"
}

prepare_automatic_iso() {
    local temporary_iso="${AUTO_ISO%.iso}.tmp.iso"

    if [[ -f "${AUTO_ISO}" &&
          "${AUTO_ISO}" -nt "${PROXMOX_ISO_PATH}" &&
          "${AUTO_ISO}" -nt "${ANSWER_FILE}" ]]; then
        log_ok "La ISO desatendida de Proxmox ya está preparada"
        return 0
    fi

    rm -f "${temporary_iso}"
    log_info "Preparando la ISO desatendida de Proxmox..."

    proxmox-auto-install-assistant prepare-iso \
        "${PROXMOX_ISO_PATH}" \
        --fetch-from iso \
        --answer-file "${ANSWER_FILE}" \
        --output "${temporary_iso}"

    mv "${temporary_iso}" "${AUTO_ISO}"
    log_ok "ISO desatendida preparada correctamente"
}

create_pve_vm() {
    if vm_exists "${PVE_VM_NAME}"; then
        log_warn "La máquina ${PVE_VM_NAME} ya existe; no se vuelve a crear"
        return 0
    fi

    mkdir -p "${EQUIPMENT_VM_DIR}"

    log_info "Creando la máquina virtual ${PVE_VM_NAME}..."

    "${VBOXMANAGE_BIN}" createvm \
        --name="${PVE_VM_NAME}" \
        --ostype="Debian_64" \
        --basefolder="${EQUIPMENT_VM_DIR}" \
        --groups="${PVE_GROUP}" \
        --register

    "${VBOXMANAGE_BIN}" modifyvm "${PVE_VM_NAME}" \
        --memory="${PVE_MEMORY_MB}" \
        --cpus="${PVE_CPUS}" \
        --ioapic=on \
        --pae=on \
        --nested-hw-virt=on \
        --nested-paging=on \
        --boot1=disk \
        --boot2=dvd \
        --boot3=none \
        --boot4=none \
        --nic1=intnet \
        --intnet1="${PVE_NETWORK}" \
        --nictype1=82540EM \
        --cableconnected1=on \
        --nic2=none \
        --nic3=none \
        --nic4=none

    "${VBOXMANAGE_BIN}" storagectl "${PVE_VM_NAME}" \
        --name="SATA" \
        --add=sata \
        --controller=IntelAhci \
        --portcount=2 \
        --bootable=on

    "${VBOXMANAGE_BIN}" createmedium disk \
        --filename="${PVE_DISK}" \
        --size="${PVE_DISK_MB}" \
        --format=VDI

    "${VBOXMANAGE_BIN}" storageattach "${PVE_VM_NAME}" \
        --storagectl="SATA" \
        --port=0 \
        --device=0 \
        --type=hdd \
        --medium="${PVE_DISK}"

    "${VBOXMANAGE_BIN}" storageattach "${PVE_VM_NAME}" \
        --storagectl="SATA" \
        --port=1 \
        --device=0 \
        --type=dvddrive \
        --medium="${AUTO_ISO}"

    log_ok "${PVE_VM_NAME} creada con red ${PVE_NETWORK} y virtualización anidada"
}

start_installation() {
    local vm_state

    if [[ -f "${INSTALL_MARKER}" ]]; then
        log_warn "La instalación de ${PVE_VM_NAME} ya fue iniciada"
        return 0
    fi

    vm_state="$("${VBOXMANAGE_BIN}" showvminfo "${PVE_VM_NAME}" \
        --machinereadable | sed -n 's/^VMState="\([^"]*\)"/\1/p')"

    if [[ "${vm_state}" != "poweroff" ]]; then
        log_err "${PVE_VM_NAME} debe estar apagada antes de iniciar la instalación"
        return 1
    fi

    "${VBOXMANAGE_BIN}" startvm "${PVE_VM_NAME}" --type=headless
    touch "${INSTALL_MARKER}"
    log_ok "Instalación desatendida de ${PVE_VM_NAME} iniciada"
}

check_requirements

if "${VBOXMANAGE_BIN}" showvminfo "${PVE_VM_NAME}" >/dev/null 2>&1; then
    log_warn "${PVE_VM_NAME} ya existe; no se vuelve a desplegar"
    exit 0
fi
download_proxmox_iso
render_answer_file
prepare_automatic_iso
create_pve_vm
start_installation

log_ok "Despliegue de Proxmox iniciado correctamente"
