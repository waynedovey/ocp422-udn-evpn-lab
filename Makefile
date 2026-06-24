SITE ?= site_a
REMOTE_VM_IP ?= 
SKIP_NESTED_CHECK ?= false
CONFIRM_NESTED_ENABLE ?= false
CLEAN_ARTIFACTS ?= false
CONFIRM_DESTROY ?= false
SHOW_KUBEADMIN_PASSWORD ?= false

.PHONY: deps ping prepare discover render install evpn test verify all nested-check destroy destroy-all destroy-site-a destroy-site-b nested-status nested-enable virt nmstate vms verify-vms

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
	ansible-playbook playbooks/08_check_nested_virt.yml --limit $(SITE) --ask-vault-pass -e nested_virt_required=false

evpn:
	ansible-playbook playbooks/05_configure_evpn.yml --limit $(SITE) --ask-vault-pass

test:
	ansible-playbook playbooks/06_deploy_test_workloads.yml --limit $(SITE) --ask-vault-pass

verify:
	ansible-playbook playbooks/07_verify.yml --limit $(SITE) --ask-vault-pass -e show_kubeadmin_password=$(SHOW_KUBEADMIN_PASSWORD)

all: prepare render install evpn test verify

install-status:
	ansible $${SITE}-bastion -m shell -a 'INSTALL_DIR=/home/lab-user/ocp422-udn-evpn-lab/artifacts/$${SITE}; echo "### PID"; cat $$INSTALL_DIR/.install.pid 2>/dev/null || true; echo "### RC"; cat $$INSTALL_DIR/.install.rc 2>/dev/null || true; echo "### Last logs"; tail -80 $$INSTALL_DIR/install-wrapper.log 2>/dev/null || tail -80 $$INSTALL_DIR/.openshift_install.log 2>/dev/null || true' --ask-vault-pass

nested-check:
	ansible-playbook playbooks/08_check_nested_virt.yml --limit $(SITE) --ask-vault-pass -e nested_virt_required=true

destroy:
	ansible-playbook playbooks/99_destroy_cluster.yml --limit $(SITE) --ask-vault-pass -e confirm_destroy=$(CONFIRM_DESTROY) -e cleanup_artifacts=$(CLEAN_ARTIFACTS)

destroy-site-a:
	$(MAKE) destroy SITE=site_a CONFIRM_DESTROY=$(CONFIRM_DESTROY) CLEAN_ARTIFACTS=$(CLEAN_ARTIFACTS)

destroy-site-b:
	$(MAKE) destroy SITE=site_b CONFIRM_DESTROY=$(CONFIRM_DESTROY) CLEAN_ARTIFACTS=$(CLEAN_ARTIFACTS)

destroy-all:
	$(MAKE) destroy SITE=site_a CONFIRM_DESTROY=$(CONFIRM_DESTROY) CLEAN_ARTIFACTS=$(CLEAN_ARTIFACTS)
	$(MAKE) destroy SITE=site_b CONFIRM_DESTROY=$(CONFIRM_DESTROY) CLEAN_ARTIFACTS=$(CLEAN_ARTIFACTS)


nested-status:
	ansible-playbook playbooks/08_check_nested_virt.yml --limit $(SITE) --ask-vault-pass -e nested_virt_required=false


nested-enable:
	ansible-playbook playbooks/09_enable_nested_virt_vmware.yml --limit $(SITE) --ask-vault-pass -e confirm_nested_enable=$(CONFIRM_NESTED_ENABLE)

virt:
	@if [ "$(SKIP_NESTED_CHECK)" != "true" ]; then \
		ansible-playbook playbooks/08_check_nested_virt.yml --limit $(SITE) --ask-vault-pass -e nested_virt_required=true; \
	fi
	ansible-playbook playbooks/10_install_virtualization.yml --limit $(SITE) --ask-vault-pass

nmstate:
	ansible-playbook playbooks/11_install_nmstate.yml --limit $(SITE) --ask-vault-pass

vms:
	ansible-playbook playbooks/12_deploy_udn_vms.yml --limit $(SITE) --ask-vault-pass

verify-vms:
	ansible-playbook playbooks/13_verify_udn_vms.yml --limit $(SITE) --ask-vault-pass -e remote_vm_ip=$(REMOTE_VM_IP)

