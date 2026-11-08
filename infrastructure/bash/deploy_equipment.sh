#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

SERVER_TEMPLATE="${DEBIAN_SERVER_TEMPLATE_NAME:-debian-server-template}"
DESKTOP_TEMPLATE="${DEBIAN_DESKTOP_TEMPLATE_NAME:-debian-desktop-template}"

EQUIPMENT_VM_DIR="${ARTIFACTS_DIR}/vms/equipment"

declare -a EQUIPMENT=(
    # Servidores principales
    "dbsrv|server|privada"
    "infosrv|server|privada"
    "websrv|server|dmz"

    # Proyectos 1 y 2 de la planta 1
    "prj1-web|server|pl1"
    "prj1-data|server|pl1"
    "prj2-web|server|pl1"
    "prj2-data|server|pl1"

    # Proyecto 3 de la planta 2
    "prj3-web|server|pl2"
    "prj3-data|server|pl2"

    # Impresoras
    "printer0|printer|pl0"
    "printer1|printer|pl1"
    "printer2|printer|pl2"
    "printer3|printer|pl3"

    # Planta baja
    "expo1|desktop|pl0"
    "expo2|desktop|pl0"
    "expo3|desktop|pl0"
    "expo4|desktop|pl0"
    "conserge1|desktop|pl0"
    "conserge2|desktop|pl0"
)

# Diez equipos de desarrollo en cada planta
for number in $(seq -w 1 10); do
    EQUIPMENT+=("dev1-${number}|desktop|pl1")
    EQUIPMENT+=("dev2-${number}|desktop|pl2")
done

# Siete equipos corporativos y tres de dirección
for number in $(seq -w 1 7); do
    EQUIPMENT+=("corp-${number}|desktop|pl3")
done

for number in $(seq -w 1 3); do
    EQUIPMENT+=("direccion-${number}|desktop|pl3-direccio")
done

vm_exists() {
    "${VBOXMANAGE_BIN}" showvminfo "$1" >/dev/null 2>&1
}

check_template() {
    local template="$1"

    if ! vm_exists "${template}"; then
        log_err "No existe el template ${template}"
        return 1
    fi

    if ! "${VBOXMANAGE_BIN}" snapshot "${template}" list \
        --machinereadable 2>/dev/null |
        grep -q 'SnapshotName.*="base-clean"'; then

        log_err "${template} no tiene la instantánea base-clean"
        return 1
    fi
}

create_linked_clone() {
    local name="$1"
    local type="$2"
    local network="$3"

    local template
    local group
    local memory
    local cpus

    case "${type}" in
        server)
            template="${SERVER_TEMPLATE}"
            group="/VirtualCorp/Equipment/Servers"
            memory=1024
            cpus=1
            ;;
        printer)
            template="${SERVER_TEMPLATE}"
            group="/VirtualCorp/Equipment/Printers"
            memory=768
            cpus=1
            ;;
        desktop)
            template="${DESKTOP_TEMPLATE}"
            group="/VirtualCorp/Equipment/Desktops"
            memory=2048
            cpus=2
            ;;
        *)
            log_err "Tipo de equipo desconocido: ${type}"
            return 1
            ;;
    esac

    if vm_exists "${name}"; then
        log_warn "${name} ya existe; no se vuelve a crear"
        return 0
    fi

    log_info "Creando ${name} desde ${template}..."

    "${VBOXMANAGE_BIN}" clonevm "${template}" \
        --snapshot="base-clean" \
        --options="link" \
        --name="${name}" \
        --basefolder="${EQUIPMENT_VM_DIR}" \
        --groups="${group}" \
        --register

    "${VBOXMANAGE_BIN}" modifyvm "${name}" \
        --memory="${memory}" \
        --cpus="${cpus}" \
        --boot1=disk \
        --boot2=none \
        --boot3=none \
        --boot4=none \
        --nic1=intnet \
        --intnet1="${network}" \
        --cableconnected1=on \
        --nic2=none \
        --nic3=none \
        --nic4=none

    log_ok "${name} conectado a ${network}"
}

check_template "${SERVER_TEMPLATE}"
check_template "${DESKTOP_TEMPLATE}"

mkdir -p "${EQUIPMENT_VM_DIR}"

for entry in "${EQUIPMENT[@]}"; do
    IFS='|' read -r name type network <<< "${entry}"
    create_linked_clone "${name}" "${type}" "${network}"
done

log_ok "Equipos Debian desplegados correctamente"
