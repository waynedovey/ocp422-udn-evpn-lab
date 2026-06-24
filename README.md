# OpenShift 4.22 UDN EVPN Lab

A hands-on lab for building and validating an inter-site EVPN fabric for OpenShift 4.22 using:

- `ClusterUserDefinedNetwork`
- OVN-Kubernetes primary UDN
- FRR-K8s
- Bastion-based FRR routing
- BGP EVPN
- OpenShift Virtualization
- Kubernetes NMState

The goal is to prove a stretched tenant Layer 2 network across two OpenShift clusters using a shared EVPN VNI and route target.

This lab first proves pod-to-pod connectivity across sites. The next phase extends the same tenant network to OpenShift Virtualization VMs.

---

## Lab Goal

This lab proves the following pattern:

```text
Site-A VM / Pod
10.100.10.x
   |
Primary UDN / ovn-udn1
VNI 10010 / RT 64520:10010
   |
Site-A FRR-K8s ASN 64520
   |
Site-A Bastion FRR ASN 64512
   |
BGP EVPN inter-site
   |
Site-B Bastion FRR ASN 64512
   |
Site-B FRR-K8s ASN 64521
   |
Primary UDN / ovn-udn1
   |
Site-B VM / Pod
10.100.10.y
```

This is best described as:

> **A stretched tenant Layer 2 network over EVPN.**

It is not the same thing as stretching a physical VMware VLAN end-to-end.

---

## High-Level Architecture

```mermaid
flowchart LR
    subgraph SITEA["Site-A / OpenShift Cluster 9wnp4"]
        A_NS["Namespace: tenant-a<br/>Primary UDN enabled"]
        A_POD["Test Pod<br/>10.100.10.14<br/>ovn-udn1"]
        A_VM["Future Test VM<br/>10.100.10.x<br/>l2bridge / primary UDN"]
        A_NODES["OpenShift Nodes<br/>192.168.69.41<br/>192.168.69.137<br/>192.168.69.138"]
        A_FRRK8S["FRR-K8s<br/>OCP ASN 64520"]
        A_BASTION["Bastion FRR<br/>192.168.69.10<br/>Fabric ASN 64512"]

        A_NS --> A_POD
        A_NS --> A_VM
        A_POD --> A_NODES
        A_VM --> A_NODES
        A_NODES --> A_FRRK8S
        A_FRRK8S --> A_BASTION
    end

    subgraph EVPN["Inter-Site EVPN Fabric"]
        FABRIC["BGP EVPN<br/>VNI 10010<br/>Route Target 64520:10010<br/>Tenant subnet 10.100.10.0/24"]
    end

    subgraph SITEB["Site-B / OpenShift Cluster rhdz5"]
        B_BASTION["Bastion FRR<br/>192.168.70.10<br/>Fabric ASN 64512"]
        B_FRRK8S["FRR-K8s<br/>OCP ASN 64521"]
        B_NODES["OpenShift Nodes<br/>192.168.70.41<br/>192.168.70.73<br/>192.168.70.137"]
        B_NS["Namespace: tenant-a<br/>Primary UDN enabled"]
        B_POD["Test Pod<br/>10.100.10.9 / 10.100.10.11<br/>ovn-udn1"]
        B_VM["Future Test VM<br/>10.100.10.y<br/>l2bridge / primary UDN"]

        B_BASTION --> B_FRRK8S
        B_FRRK8S --> B_NODES
        B_NODES --> B_POD
        B_NODES --> B_VM
        B_NS --> B_POD
        B_NS --> B_VM
    end

    A_BASTION <-->|"iBGP EVPN<br/>64512 ↔ 64512"| FABRIC
    FABRIC <-->|"iBGP EVPN<br/>64512 ↔ 64512"| B_BASTION

    A_POD <-. "Validated cross-site pod ping" .-> B_POD
    A_VM <-. "Next phase: cross-site VM ping" .-> B_VM
```

---

## Final Working EVPN Design

| Component | Site-A | Site-B |
|---|---:|---:|
| Cluster name | `9wnp4` | `rhdz5` |
| Base domain | `dynamic2.redhatworkshops.io` | `dynamic2.redhatworkshops.io` |
| Underlay subnet | `192.168.69.0/24` | `192.168.70.0/24` |
| Bastion IP | `192.168.69.10` | `192.168.70.10` |
| Bastion / fabric ASN | `64512` | `64512` |
| OpenShift FRR-K8s ASN | `64520` | `64521` |
| EVPN VNI | `10010` | `10010` |
| EVPN route target | `64520:10010` | `64520:10010` |
| Tenant namespace | `tenant-a` | `tenant-a` |
| Tenant subnet | `10.100.10.0/24` | `10.100.10.0/24` |

---

## Why Site-B Uses ASN 64521

Site-A and Site-B must not use the same OpenShift FRR-K8s ASN.

If both clusters use `64520`, remote EVPN routes can be rejected by BGP loop prevention because the receiving OpenShift FRR speaker sees its own ASN in the AS path.

Working configuration:

```yaml
# Site-A
ocp_bgp_asn: 64520
evpn_route_target_base: 64520

# Site-B
ocp_bgp_asn: 64521
evpn_route_target_base: 64520
```

The OpenShift ASNs are different, but the EVPN route target stays the same:

```text
64520:10010
```

That shared route target is what lets both clusters import and export the same tenant EVPN network.

---

## Required Inter-Site FRR Routes

The bastions need routes to the full remote underlay subnet, not only to the remote bastion `/32`.

A `/32` route to the remote bastion is enough to establish the BGP session, but it is not enough for the EVPN data plane. EVPN next-hops point to remote OpenShift node VTEPs, so each side must reach the full remote node underlay subnet.

### Site-A FRR

```text
ip route 192.168.70.0/24 192.168.69.1
neighbor 192.168.70.10 remote-as 64512
```

### Site-B FRR

```text
ip route 192.168.69.0/24 192.168.70.1
neighbor 192.168.69.10 remote-as 64512
```

---

## Repository Layout

```text
ocp422-udn-evpn-lab/
├── ansible.cfg
├── Makefile
├── README.md
├── requirements.yml
├── inventories/
│   └── lab/
│       ├── hosts.yml
│       └── group_vars/
│           ├── all/
│           │   ├── vars.yml
│           │   └── vault.yml
│           ├── site_a.yml
│           └── site_b.yml
├── playbooks/
│   ├── 01_prepare_bastion.yml
│   ├── 02_vsphere_discover.yml
│   ├── 03_render_install_config.yml
│   ├── 04_install_cluster.yml
│   ├── 05_configure_evpn.yml
│   ├── 06_deploy_test_workloads.yml
│   ├── 07_verify.yml
│   ├── 08_check_nested_virt.yml
│   ├── 09_enable_nested_virt_vmware.yml
│   └── 99_destroy_cluster.yml
└── templates/
    ├── install-config.yaml.j2
    ├── frr.conf.j2
    ├── evpn-vxlan.service.j2
    └── manifests/
        ├── vtep.yaml.j2
        ├── frrconfiguration.yaml.j2
        ├── routeadvertisements.yaml.j2
        ├── cudn.yaml.j2
        └── test-pod.yaml.j2
```

---

## Current Validated State

The pod-based EVPN lab has been validated successfully.

```text
Site-A local EVPN:        Working
Site-B local EVPN:        Working
Site-A <-> Site-B BGP:    Established
Remote VTEP reachability: Working
Remote Type-2 routes:     Learned by bastions and node FRR pods
Pod-to-pod UDN ping:      Working both ways
```

Validated pod traffic:

```text
Site-A pod 10.100.10.14 -> Site-B pod 10.100.10.9: success
Site-B pod 10.100.10.11 -> Site-A pod 10.100.10.14: success
```

Expected result:

```text
3 packets transmitted, 3 received, 0% packet loss
```

---

## Current Nested Virtualization State

Nested virtualization has been checked on both clusters.

Current result:

```text
CPU virtualization flags: MISSING
/dev/kvm: MISSING
```

This means OpenShift Virtualization can be installed, but VM workloads will not run with hardware acceleration until VMware exposes nested virtualization to the OpenShift node VMs.

Expected fixed result:

```text
CPU virtualization flags: vmx or svm present
/dev/kvm: present
NESTED_VIRT_STATUS=OK
```

---

## Make Targets

| Target | Example | Description |
|---|---|---|
| `prepare` | `make prepare SITE=site_a` | Prepare the bastion host. |
| `discover` | `make discover SITE=site_a` | Discover vSphere details. |
| `render` | `make render SITE=site_a` | Render OpenShift install config. |
| `install` | `make install SITE=site_a` | Install OpenShift, then run a non-fatal nested virt status check. |
| `evpn` | `make evpn SITE=site_a` | Configure FRR, EVPN, VTEP, RouteAdvertisements and CUDN. |
| `test` | `make test SITE=site_a` | Deploy tenant test pods. |
| `verify` | `make verify SITE=site_a` | Verify cluster, EVPN and access status. |
| `nested-status` | `make nested-status SITE=site_a` | Check nested virtualization without failing the run. |
| `nested-check` | `make nested-check SITE=site_a` | Strict nested virtualization check. Fails if `/dev/kvm` is missing. |
| `nested-enable` | `make nested-enable SITE=site_a CONFIRM_NESTED_ENABLE=true` | Enable VMware nested virtualization one node at a time. |
| `destroy` | `make destroy SITE=site_a CONFIRM_DESTROY=true` | Destroy one OpenShift cluster. |
| `destroy-all` | `make destroy-all CONFIRM_DESTROY=true` | Destroy both OpenShift clusters. |

---

## Deployment Flow

### Site-A

```bash
make prepare SITE=site_a
make discover SITE=site_a
make render SITE=site_a
make install SITE=site_a
make evpn SITE=site_a
make test SITE=site_a
make verify SITE=site_a
```

### Site-B

```bash
make prepare SITE=site_b
make discover SITE=site_b
make render SITE=site_b
make install SITE=site_b
make evpn SITE=site_b
make test SITE=site_b
make verify SITE=site_b
```

---

## Verify Options

The `verify` target checks the status of a deployed site.

### Basic Usage

```bash
make verify SITE=site_a
make verify SITE=site_b
```

By default, `verify` shows:

- Cluster status
- EVPN status
- OpenShift Console URL
- `kubeadmin` username
- Hidden password message

The `kubeadmin` password is hidden by default so it is not accidentally leaked into terminal history, screenshots, Slack, Git commits, or support case logs.

### Options

| Option | Default | Example | Description |
|---|---:|---|---|
| `SITE` | `site_a` | `SITE=site_b` | Selects which site to verify. |
| `SHOW_KUBEADMIN_PASSWORD` | `false` | `SHOW_KUBEADMIN_PASSWORD=true` | Prints the `kubeadmin` password during verify. |

### Show Console URL and Username

```bash
make verify SITE=site_a
make verify SITE=site_b
```

Expected output includes:

```text
# Cluster access
Console URL:
https://console-openshift-console.apps.<cluster>.<base-domain>

Username:
kubeadmin

Password:
hidden - run: make verify SITE=<site> SHOW_KUBEADMIN_PASSWORD=true
```

### Show kubeadmin Password

Only use this when you really need the password:

```bash
make verify SITE=site_a SHOW_KUBEADMIN_PASSWORD=true
make verify SITE=site_b SHOW_KUBEADMIN_PASSWORD=true
```

---

## Nested Virtualization Checks

### Warning-Only Status Check

Use this when you want to see the status but not fail the command:

```bash
make nested-status SITE=site_a
make nested-status SITE=site_b
```

### Strict Check

Use this before installing OpenShift Virtualization or running VMs:

```bash
make nested-check SITE=site_a
make nested-check SITE=site_b
```

If nested virtualization is missing, this target fails intentionally.

Expected failure:

```text
NESTED_VIRT_STATUS=MISSING
Nested virtualization is required but /dev/kvm is missing on one or more nodes.
```

Expected success:

```text
NESTED_VIRT_STATUS=OK
Nested virtualization is available on all nodes.
```

---

## Enable Nested Virtualization on VMware

Nested virtualization must be enabled on the VMware VMs that run the OpenShift nodes.

The automated target powers off and updates one OpenShift node VM at a time.

> **Warning**
>
> These clusters are compact control-plane clusters. Do not power off all nodes at once.

### Enable on Site-A

```bash
make nested-enable SITE=site_a CONFIRM_NESTED_ENABLE=true
make nested-check SITE=site_a
```

### Enable on Site-B

```bash
make nested-enable SITE=site_b CONFIRM_NESTED_ENABLE=true
make nested-check SITE=site_b
```

### Enable on One Node First

This is safer when testing the automation:

```bash
ansible-playbook playbooks/09_enable_nested_virt_vmware.yml \
  --limit site_a \
  --ask-vault-pass \
  -e confirm_nested_enable=true \
  -e nested_virt_nodes=9wnp4-gll82-master-0
```

Then verify:

```bash
make nested-check SITE=site_a
```

The playbook does the following for each node:

```text
1. Cordon OpenShift node
2. Drain OpenShift node
3. Power off VMware VM
4. Enable nested virtualization
5. Power on VMware VM
6. Wait for OpenShift node Ready
7. Uncordon OpenShift node
8. Continue to next node
```

---

## OpenShift Virtualization and NMState Phase

After nested virtualization is working, the next phase is:

```text
1. Install OpenShift Virtualization on Site-A and Site-B
2. Install Kubernetes NMState Operator on Site-A and Site-B
3. Deploy one test VM on Site-A attached to the primary UDN
4. Deploy one test VM on Site-B attached to the primary UDN
5. Confirm both VMs receive addresses from 10.100.10.0/24
6. Ping VM-to-VM across the EVPN fabric
```

Recommended future Make targets:

```makefile
virt:
	ansible-playbook playbooks/10_install_virtualization.yml --limit $(SITE) --ask-vault-pass

nmstate:
	ansible-playbook playbooks/11_install_nmstate.yml --limit $(SITE) --ask-vault-pass

vms:
	ansible-playbook playbooks/12_deploy_udn_vms.yml --limit $(SITE) --ask-vault-pass

verify-vms:
	ansible-playbook playbooks/13_verify_udn_vms.yml --limit $(SITE) --ask-vault-pass
```

---

## VM Stretch Goal

The next validation target is:

| VM | Site | Expected network |
|---|---|---|
| `site-a-udn-vm` | Site-A | `10.100.10.x/24` on primary UDN |
| `site-b-udn-vm` | Site-B | `10.100.10.y/24` on primary UDN |

Expected result:

```text
site-a-udn-vm -> site-b-udn-vm: success
site-b-udn-vm -> site-a-udn-vm: success
```

This proves the tenant L2 network is stretched across clusters for VM workloads, not only pod workloads.

---

## EVPN Validation Commands

### Bastion BGP Summary

Site-A:

```bash
ansible site-a-bastion \
  -m shell \
  -a 'sudo vtysh -c "show bgp l2vpn evpn summary"' \
  --ask-vault-pass -o
```

Site-B:

```bash
ansible site-b-bastion \
  -m shell \
  -a 'sudo vtysh -c "show bgp l2vpn evpn summary"' \
  --ask-vault-pass -o
```

Expected:

```text
Site-A OCP node peers: AS 64520 up
Site-B OCP node peers: AS 64521 up
Site-A <-> Site-B bastion peer: AS 64512 up
```

### Site-A Should Learn Site-B Routes

```bash
ansible site-a-bastion \
  -m shell \
  -a 'sudo vtysh -c "show bgp l2vpn evpn" | egrep "192.168.70|10.100.10.9|10.100.10.11|RT:64520:10010"' \
  --ask-vault-pass -o
```

Expected routes include:

```text
10.100.10.9
10.100.10.11
192.168.70.41
192.168.70.73
192.168.70.137
```

### Site-B Should Learn Site-A Routes

```bash
ansible site-b-bastion \
  -m shell \
  -a 'sudo vtysh -c "show bgp l2vpn evpn" | egrep "192.168.69|10.100.10.12|10.100.10.14|RT:64520:10010"' \
  --ask-vault-pass -o
```

Expected routes include:

```text
10.100.10.12
10.100.10.14
192.168.69.41
192.168.69.137
192.168.69.138
```

---

## Pod-to-Pod Proof

### Site-A Pod to Site-B Pod

```bash
ansible site-a-bastion \
  -m shell \
  -a 'export KUBECONFIG=/home/lab-user/ocp422-udn-evpn-lab/artifacts/site_a/auth/kubeconfig; POD=$(oc -n tenant-a get pods -l app=evpn-test --field-selector=status.phase=Running -o jsonpath="{.items[0].metadata.name}"); oc -n tenant-a exec $POD -- ping -I ovn-udn1 -c 3 10.100.10.9' \
  --ask-vault-pass -o
```

### Site-B Pod to Site-A Pod

```bash
ansible site-b-bastion \
  -m shell \
  -a 'export KUBECONFIG=/home/lab-user/ocp422-udn-evpn-lab/artifacts/site_b/auth/kubeconfig; POD=$(oc -n tenant-a get pods -l app=evpn-test --field-selector=status.phase=Running -o jsonpath="{.items[0].metadata.name}"); oc -n tenant-a exec $POD -- ping -I ovn-udn1 -c 3 10.100.10.14' \
  --ask-vault-pass -o
```

Expected:

```text
3 packets transmitted, 3 received, 0% packet loss
```

---

## Cluster Teardown

Destroy one site:

```bash
make destroy SITE=site_a CONFIRM_DESTROY=true
make destroy SITE=site_b CONFIRM_DESTROY=true
```

Destroy both sites:

```bash
make destroy-all CONFIRM_DESTROY=true
```

Destroy both sites and remove install artifacts from the bastions:

```bash
make destroy-all CONFIRM_DESTROY=true CLEAN_ARTIFACTS=true
```

The destroy target uses:

```bash
openshift-install destroy cluster --dir <install_dir>
```

The destroy playbook refuses to run unless `CONFIRM_DESTROY=true` is provided.

---

## Troubleshooting

### BGP Peer Is Stuck in Active

Check reachability to the remote bastion:

```bash
sudo vtysh -c "show bgp neighbors <remote-bastion-ip>"
sudo vtysh -c "show ip route <remote-bastion-ip>"
ip route get <remote-bastion-ip>
```

If FRR reports:

```text
No path to specified Neighbor
```

Check that the remote underlay route exists.

### BGP Is Up but Cross-Site Ping Fails

Check remote Type-2 EVPN routes.

Site-A should learn Site-B pod or VM routes:

```bash
oc -n openshift-frr-k8s exec <frr-pod> -c frr -- \
  vtysh -c "show bgp l2vpn evpn" | egrep "10.100.10.9|10.100.10.11"
```

Site-B should learn Site-A pod or VM routes:

```bash
oc -n openshift-frr-k8s exec <frr-pod> -c frr -- \
  vtysh -c "show bgp l2vpn evpn" | egrep "10.100.10.12|10.100.10.14"
```

Check:

- Site-A OpenShift ASN is `64520`
- Site-B OpenShift ASN is `64521`
- Both sites share route target `64520:10010`
- Both bastions can reach the full remote underlay subnet
- OCP nodes can reach remote VTEP addresses

### CUDN Spec Is Immutable

If you see:

```text
The ClusterUserDefinedNetwork "tenant-a-l2" is invalid: spec.network: Invalid value: Network spec is immutable
```

Do not change the VNI, route target, topology, transport or subnet on an existing CUDN.

The working shared route target is:

```text
64520:10010
```

If the CUDN must change, delete and recreate it only when it is safe to disrupt the tenant network.

### OpenShift Virtualization VMs Do Not Start

Check nested virtualization first:

```bash
make nested-check SITE=site_a
make nested-check SITE=site_b
```

If `/dev/kvm` is missing, enable nested virtualization on the VMware node VMs.

---

## Security Notes

Do not commit or paste any of the following:

```text
kubeadmin-password
kubeconfig
pull-secret
vault.yml
terminal output containing vault passwords
```

If a vault password, kubeadmin password, pull secret, or kubeconfig is pasted into chat, Slack, a ticket, a recording, or a Git repository by mistake, rotate it.

Recommended `.gitignore` entries:

```gitignore
inventories/lab/group_vars/all/vault.yml
artifacts/
*.kubeconfig
kubeadmin-password
pull-secret.json
```

---

## Final Known Good Result

The current lab proves end-to-end EVPN UDN connectivity for pods across two OpenShift clusters:

```text
Site-A pod 10.100.10.14 -> Site-B pod 10.100.10.9: success
Site-B pod 10.100.10.11 -> Site-A pod 10.100.10.14: success
```

The next milestone is to prove the same pattern with VMs:

```text
Site-A VM 10.100.10.x -> Site-B VM 10.100.10.y
Site-B VM 10.100.10.y -> Site-A VM 10.100.10.x
```

That will confirm the tenant Layer 2 network is stretched across both OpenShift clusters for both pods and virtual machines.
