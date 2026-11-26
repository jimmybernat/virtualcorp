locals {
  ansible_inventory = {
    all = {
      children = {
        proxmox_lxc = {
          children = {
            terraform_services = {
              hosts = {
                dhcp01 = {
                  hostname          = var.container_hostname
                  vcorp_mac_address = proxmox_virtual_environment_container.dhcp01.network_interface[0].mac_address
                  vcorp_network     = "privada"
                  vcorp_ipv4_cidr   = var.container_ipv4
                  ansible_host      = split("/", var.container_ipv4)[0]
                }

                dns01 = {
                  hostname          = var.dns01_hostname
                  vcorp_mac_address = proxmox_virtual_environment_container.dns01.network_interface[0].mac_address
                  vcorp_network     = "privada"
                }
              }
            }

            kea_dhcp = {
              hosts = {
                dhcp01 = {}
              }
            }

            bind_dns = {
              hosts = {
                dns01 = {}
              }
            }
          }

          vars = {
            ansible_user                 = "root"
            ansible_ssh_private_key_file = "/home/jimmy/.ssh/vcorp_sysadmin"
            ansible_python_interpreter   = "/usr/bin/python3"
          }
        }
      }
    }
  }
}

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../../../automation/ansible/inventories/proxmox_lxc.yml"
  content         = yamlencode(local.ansible_inventory)
  file_permission = "0644"

  depends_on = [
    proxmox_virtual_environment_container.dhcp01,
    proxmox_virtual_environment_container.dns01
  ]
}
