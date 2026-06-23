# Lab topology

This repo treats each vSphere workshop sandbox as an independent EVPN lab site.

```text
Site-A: 192.168.69.0/24
  bastion / FRR fabric peer
  OCP 4.22 compact cluster on segment-sandbox-9wnp4
  API VIP: 192.168.69.201
  Ingress VIP: 192.168.69.202
  VTEP CIDR: 192.168.69.0/24

Site-B: 192.168.70.0/24
  bastion / FRR fabric peer
  OCP 4.22 compact cluster on segment-sandbox-rhdz5
  API VIP: 192.168.70.201
  Ingress VIP: 192.168.70.202
  VTEP CIDR: 192.168.70.0/24
```

Why use the underlay subnet as the VTEP CIDR?

For this VMware simulation, it is simpler to use the node InternalIP addresses as VTEP addresses. That means no dummy VTEP interfaces or static routes are needed just to make the bastion and nodes reachable. In a real bare-metal lab, you can move to dedicated VTEP loopbacks or routed loopbacks later.

This lab does not assume Site-A and Site-B have routed private connectivity to each other. It builds the same EVPN pattern in each site. Cross-site EVPN can be added later with WireGuard/IPsec underlay routing between bastions and routed VTEP reachability.
