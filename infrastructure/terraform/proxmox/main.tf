terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.112.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = var.proxmox_insecure
}

resource "proxmox_virtual_environment_container" "dhcp01" {
  description = "Servidor Kea DHCP de VirtualCorp gestionado con Terraform"

  node_name = var.proxmox_node
  vm_id     = var.container_vm_id

  started       = true
  start_on_boot = true
  unprivileged  = true

  tags = [
    "virtualcorp",
    "dhcp",
    "terraform"
  ]

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
    swap      = 0
  }

  disk {
    datastore_id = var.container_datastore
    size         = 6
  }

  features {
    nesting = true
  }

  initialization {
    hostname = var.container_hostname

    dns {
      servers = [var.container_dns]
    }

    ip_config {
      ipv4 {
        address = var.container_ipv4
        gateway = var.container_gateway
      }
    }

    user_account {
      keys = [
        for key_file in var.ssh_public_key_files :
        trimspace(file("${path.module}/${key_file}"))
      ]
    }
  }

  network_interface {
    name     = "eth0"
    bridge   = var.container_bridge
    enabled  = true
    firewall = false
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = "debian"
  }
}

resource "proxmox_virtual_environment_container" "dns01" {
  description = "Servidor BIND9 DNS de VirtualCorp gestionado con Terraform"

  node_name = var.proxmox_node
  vm_id     = var.dns01_vm_id

  started       = true
  start_on_boot = true
  unprivileged  = true

  tags = [
    "virtualcorp",
    "dns",
    "terraform"
  ]

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
    swap      = 0
  }

  disk {
    datastore_id = var.container_datastore
    size         = 6
  }

  features {
    nesting = true
  }

  initialization {
    hostname = var.dns01_hostname

    dns {
      servers = [var.container_dns]
    }

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      keys = [
        for key_file in var.ssh_public_key_files :
        trimspace(file("${path.module}/${key_file}"))
      ]
    }
  }

  network_interface {
    name        = "eth0"
    bridge      = var.container_bridge
    enabled     = true
    firewall    = false
    mac_address = var.dns01_mac_address
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = "debian"
  }

  depends_on = [
    proxmox_virtual_environment_container.dhcp01
  ]
}

output "dhcp01_vm_id" {
  description = "VMID asignado al contenedor DHCP"
  value       = proxmox_virtual_environment_container.dhcp01.vm_id
}

output "dhcp01_ipv4" {
  description = "Dirección IPv4 del servidor DHCP"
  value       = var.container_ipv4
}

output "dns01_vm_id" {
  description = "VMID asignado al contenedor DNS"
  value       = proxmox_virtual_environment_container.dns01.vm_id
}

output "dns01_mac_address" {
  description = "MAC utilizada por dns01 para obtener su reserva DHCP"
  value       = proxmox_virtual_environment_container.dns01.network_interface[0].mac_address
}
