SITE ?= site_a

.PHONY: deps ping prepare discover render install evpn test verify all

deps:
	ansible-galaxy collection install -r requirements.yml

ping:
	ansible -i inventories/lab/hosts.yml $(SITE) -m ping --ask-vault-pass

prepare:
	ansible-playbook playbooks/01_prepare_bastion.yml --limit $(SITE) --ask-vault-pass

discover:
	ansible-playbook playbooks/02_vsphere_discover.yml --limit $(SITE) --ask-vault-pass

render:
	ansible-playbook playbooks/03_render_install_config.yml --limit $(SITE) --ask-vault-pass

install:
	ansible-playbook playbooks/04_install_cluster.yml --limit $(SITE) --ask-vault-pass

evpn:
	ansible-playbook playbooks/05_configure_evpn.yml --limit $(SITE) --ask-vault-pass

test:
	ansible-playbook playbooks/06_deploy_test_workloads.yml --limit $(SITE) --ask-vault-pass

verify:
	ansible-playbook playbooks/07_verify.yml --limit $(SITE) --ask-vault-pass

all: prepare render install evpn test verify
