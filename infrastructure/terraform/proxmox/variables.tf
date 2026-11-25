variable "proxmox_endpoint" {
  description = "Dirección de la API de Proxmox VE"
  type        = string
}

variable "proxmox_node" {
  description = "Nombre del nodo Proxmox"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Identificador del token API de Terraform"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "Secreto del token API de Terraform"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Permite el certificado autofirmado del laboratorio"
  type        = bool
  default     = true
}

variable "container_vm_id" {
  description = "Identificador del contenedor dhcp01"
  type        = number
  default     = 201
}

variable "container_hostname" {
  description = "Hostname del servidor DHCP"
  type        = string
  default     = "dhcp01"
}

variable "container_ipv4" {
  description = "Dirección IPv4 fija del servidor DHCP"
  type        = string
  default     = "10.21.0.136/26"
}

variable "container_gateway" {
  description = "Gateway de la red privada"
  type        = string
  default     = "10.21.0.129"
}

variable "container_dns" {
  description = "Servidor DNS provisional"
  type        = string
  default     = "8.8.8.8"
}

variable "container_bridge" {
  description = "Bridge de Proxmox conectado a la red privada"
  type        = string
  default     = "vmbr0"
}

variable "template_file_id" {
  description = "Plantilla LXC Debian 13 almacenada en Proxmox"
  type        = string
  default     = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
}

variable "container_datastore" {
  description = "Almacenamiento del disco del contenedor"
  type        = string
  default     = "local-lvm"
}

variable "ssh_public_key_files" {
  description = "Claves públicas autorizadas para administrar dhcp01"
  type        = list(string)

  default = [
    "../../../configs/ssh/vcorp_auditor.pub",
    "../../../configs/ssh/vcorp_sysadmin.pub"
  ]
}
