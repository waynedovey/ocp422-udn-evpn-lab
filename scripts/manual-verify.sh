#!/usr/bin/env bash
set -euo pipefail

: "${KUBECONFIG:?Set KUBECONFIG first}"

echo "# Nodes"
oc get nodes -o wide

echo "# EVPN objects"
oc get vtep,routeadvertisements,clusteruserdefinednetwork

echo "# FRR-K8s"
oc -n openshift-frr-k8s get pods -o wide

for p in $(oc -n openshift-frr-k8s get pods -o name); do
  echo "### $p"
  oc -n openshift-frr-k8s exec "$p" -c frr -- vtysh -c 'show bgp summary' || true
  oc -n openshift-frr-k8s exec "$p" -c frr -- vtysh -c 'show bgp l2vpn evpn summary' || true
done
