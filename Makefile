SITE ?= site_a
SHOW_KUBEADMIN_PASSWORD ?= false

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
	ansible-playbook playbooks/07_verify.yml --limit $(SITE) --ask-vault-pass -e show_kubeadmin_password=$(SHOW_KUBEADMIN_PASSWORD)

all: prepare render install evpn test verify

install-status:
	ansible $${SITE}-bastion -m shell -a 'INSTALL_DIR=/home/lab-user/ocp422-udn-evpn-lab/artifacts/$${SITE}; echo "### PID"; cat $$INSTALL_DIR/.install.pid 2>/dev/null || true; echo "### RC"; cat $$INSTALL_DIR/.install.rc 2>/dev/null || true; echo "### Last logs"; tail -80 $$INSTALL_DIR/install-wrapper.log 2>/dev/null || tail -80 $$INSTALL_DIR/.openshift_install.log 2>/dev/null || true' --ask-vault-pass
