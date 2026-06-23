# OpenShift 4.22 UDN EVPN Lab on vSphere

This repo automates a **learning lab** for OpenShift 4.22 BGP EVPN with primary ClusterUserDefinedNetwork/CUDN networks.

It is designed for the two Red Hat workshop vSphere sandboxes:

- **Site-A**: `192.168.69.0/24`, cluster domain `9wnp4.dynamic2.redhatworkshops.io`
- **Site-B**: `192.168.70.0/24`, cluster domain `rhdz5.dynamic2.redhatworkshops.io`

The bastion in each site is used as the external FRR EVPN fabric peer.

> Important: OpenShift 4.22 BGP EVPN for primary CUDNs is documented as a **bare-metal only** feature for supported deployments. This vSphere repo is for lab learning/simulation.

## Topology

```text
Site-A or Site-B

          bastion VM
          FRR external fabric peer
          ASN 64512
          VNI 10010
              |
              | BGP TCP/179 + VXLAN UDP/4789
              |
      vSphere port group / workshop segment
              |
  -----------------------------------------
  | OpenShift 4.22 compact cluster         |
  | FRR-K8s on OCP nodes                   |
  | ASN 64520                              |
  | VTEP CIDR = site subnet                |
  | CUDN tenant-a-l2                       |
  | MAC-VRF VNI 10010                      |
  -----------------------------------------
```

## What the automation does

1. Prepares the bastion with OpenShift CLI, installer and base packages.
2. Optionally discovers vSphere inventory values using `govc`.
3. Renders `install-config.yaml` for vSphere IPI.
4. Installs a compact OpenShift 4.22 cluster.
5. Configures FRR on the bastion as the external EVPN fabric peer.
6. Enables OpenShift FRR-K8s and OVN route advertisements.
7. Applies:
   - `VTEP`
   - `FRRConfiguration`
   - `RouteAdvertisements`
   - `ClusterUserDefinedNetwork`
8. Deploys a simple test workload into the primary CUDN namespace.

## Repo layout

```text
.
├── ansible.cfg
├── inventories/lab
│   ├── hosts.yml
│   └── group_vars
│       ├── all.yml
│       ├── site_a.yml
│       ├── site_b.yml
│       └── vault.example.yml
├── playbooks
│   ├── 01_prepare_bastion.yml
│   ├── 02_vsphere_discover.yml
│   ├── 03_render_install_config.yml
│   ├── 04_install_cluster.yml
│   ├── 05_configure_evpn.yml
│   ├── 06_deploy_test_workloads.yml
│   └── 07_verify.yml
├── templates
│   ├── install-config.yaml.j2
│   ├── frr.conf.j2
│   ├── evpn-vxlan.service.j2
│   └── manifests
└── scripts
    └── manual-verify.sh
```

## Setup

Install Ansible collections on your laptop/controller:

```bash
make deps
```

Create the encrypted vault file:

```bash
cp inventories/lab/group_vars/vault.example.yml inventories/lab/group_vars/vault.yml
vi inventories/lab/group_vars/vault.yml
ansible-vault encrypt inventories/lab/group_vars/vault.yml
```

Do **not** commit `vault.yml`, pull secrets, kubeconfigs, or generated `artifacts/`.

## Fill these required values

The site-specific values are already in:

```text
inventories/lab/group_vars/site_a.yml
inventories/lab/group_vars/site_b.yml
```

But a full vSphere IPI install still needs these values in `inventories/lab/group_vars/all.yml` or site-specific overrides:

```yaml
vcenter_compute_cluster: "CHANGE-ME"
vcenter_datastore: "CHANGE-ME"
vcenter_resource_pool: ""
```

Use discovery to find likely values:

```bash
make discover SITE=site_a
make discover SITE=site_b
```

## Run Site-A

```bash
make prepare SITE=site_a
make discover SITE=site_a
# edit vcenter_compute_cluster and vcenter_datastore after discovery
make render SITE=site_a
make install SITE=site_a
make evpn SITE=site_a
make test SITE=site_a
make verify SITE=site_a
```

## Run Site-B

```bash
make prepare SITE=site_b
make discover SITE=site_b
# edit vcenter_compute_cluster and vcenter_datastore after discovery
make render SITE=site_b
make install SITE=site_b
make evpn SITE=site_b
make test SITE=site_b
make verify SITE=site_b
```

## If the OpenShift cluster already exists

Copy or place the kubeconfig on the bastion at:

```text
/home/lab-user/ocp422-udn-evpn-lab/artifacts/site_a/auth/kubeconfig
/home/lab-user/ocp422-udn-evpn-lab/artifacts/site_b/auth/kubeconfig
```

Then run:

```bash
make evpn SITE=site_a
make test SITE=site_a
make verify SITE=site_a
```

## Important variables

```yaml
ocp_bgp_asn: 64520
fabric_bgp_asn: 64512
evpn_mac_vrf_vni: 10010
evpn_ip_vrf_vni: 20010
cudn_name: tenant-a-l2
cudn_namespace: tenant-a
cudn_subnet: 10.100.10.0/24
```

By default, each site uses the site subnet as the VTEP CIDR:

```yaml
evpn_vtep_cidr: "{{ subnet_cidr }}"
```

That means the OpenShift node InternalIP addresses become the VTEP addresses for this VMware simulation.

## Useful checks

On the bastion:

```bash
sudo vtysh -c 'show bgp summary'
sudo vtysh -c 'show bgp l2vpn evpn summary'
sudo vtysh -c 'show bgp l2vpn evpn'
ip -d link show vxlan10010
bridge fdb show dev vxlan10010
```

Against the cluster:

```bash
export KUBECONFIG=/home/lab-user/ocp422-udn-evpn-lab/artifacts/site_a/auth/kubeconfig
oc get vtep
oc get routeadvertisements
oc get clusteruserdefinednetwork
oc -n openshift-frr-k8s get pods -o wide
oc -n tenant-a get pods -o wide
```

## Known limitations

- vSphere is a simulation for this feature, not the supported production platform.
- This repo builds per-site EVPN labs. It does not assume Site-A and Site-B have routed private connectivity between `192.168.69.0/24` and `192.168.70.0/24`.
- Cross-site EVPN would require a routed underlay between sites, for example WireGuard/IPsec between bastions plus node/VTEP route handling.
- The default lab focuses on MAC-VRF/L2 VNI. IP-VRF/L3 VNI can be enabled later with `evpn_enable_ip_vrf: true`, but the external FRR L3 gateway configuration then needs to be completed properly.

## Working Inter-Site EVPN Design

This lab uses two OpenShift clusters connected through bastion FRR routers to prove inter-site EVPN behaviour for a primary `ClusterUserDefinedNetwork`.

The final working design uses different OpenShift FRR-K8s ASNs per site, but a shared EVPN route target.

| Component | Site-A | Site-B |
|---|---:|---:|
| Bastion / fabric ASN | `64512` | `64512` |
| OpenShift FRR-K8s ASN | `64520` | `64521` |
| EVPN route target | `64520:10010` | `64520:10010` |
| EVPN VNI | `10010` | `10010` |
| Tenant subnet | `10.100.10.0/24` | `10.100.10.0/24` |
| Underlay subnet | `192.168.69.0/24` | `192.168.70.0/24` |
| Bastion underlay IP | `192.168.69.10` | `192.168.70.10` |

### Key design notes

Site-B uses `ocp_bgp_asn: 64521` so that remote EVPN routes are not rejected by BGP AS loop prevention.

The EVPN route target remains shared across both sites:

```yaml
evpn_route_target_base: 64520
