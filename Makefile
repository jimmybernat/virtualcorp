ifeq ($(wildcard .env),)
$(error Missing .env; create it from .env.example with: cp .env.example .env)
endif

include .env

export PROJECT_ROOT ARTIFACTS_DIR CONFIGS_DIR SSH_PUBLIC_KEY_DIR SSH_PRIVATE_KEY_DIR
export ROUTEROS_VERSION ROUTEROS_VDI_FILENAME ROUTEROS_VDI_PATH ROUTEROS_BOX_NAME ROUTEROS_BOX_FILE
export DEBIAN_VERSION DEBIAN_ISO_FILENAME DEBIAN_ISO_URL DEBIAN_ISO_PATH DEBIAN_ISO_SHA256
export PROXMOX_VERSION PROXMOX_ISO_FILENAME PROXMOX_ISO_URL PROXMOX_ISO_PATH PROXMOX_ISO_SHA256
export VBOX_ROOT_GROUP VM_ROUTERS_GROUP VM_TEMPLATES_GROUP VBOXMANAGE_BIN

BASH_DIR := $(PROJECT_ROOT)/infrastructure/bash
BOOTSTRAP_DIR := $(PROJECT_ROOT)/automation/scripts/bootstrap

.PHONY: help deploy-routers delete-routers reset-routers reset_routers ssh-keys routeros-box create_templates
help:
	@printf '%s\n' \
	  'Targets:' \
	  '  deploy-routers  Create and configure the router VMs' \
	  '  delete-routers  Delete the router VM group' \
	  '  reset-routers   Delete and redeploy the router VMs' \
	  '  ssh-keys        Generate the project SSH keys' \
	  '  routeros-box    Build the RouterOS Vagrant box'\
	  '  create_templates Create the Debian Server and Desktop templates'

deploy-routers:
	"$(BASH_DIR)/deploy_routers.sh"

delete-routers:
	"$(BASH_DIR)/del_vbox_group.sh" --routers

reset-routers:
	"$(BASH_DIR)/del_vbox_group.sh" --routers
	"$(BASH_DIR)/deploy_routers.sh"

# Keep the original target name available for existing callers.
reset_routers: reset-routers

ssh-keys:
	"$(BOOTSTRAP_DIR)/create_ssh_keys.sh"

routeros-box:
	"$(BOOTSTRAP_DIR)/create_mikrotik_box.sh"
create_templates:
	"$(BASH_DIR)/create_templates.sh"
