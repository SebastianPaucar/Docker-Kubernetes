#!/bin/bash
set -euo pipefail

MASTER_NODE_HOSTNAME="lab-x38"
MASTER_NODE_PORT=6443

echo "Checking connectivity to master $MASTER_NODE_HOSTNAME:$MASTER_NODE_PORT..."
nc -zv $MASTER_NODE_HOSTNAME $MASTER_NODE_PORT
echo "Connectivity check passed."

NODE_TOKEN="<NODE_TOKEN>"

echo "Installing K3s agent on worker node..."
curl -sfL https://get.k3s.io | K3S_URL=https://$MASTER_NODE_HOSTNAME:$MASTER_NODE_PORT K3S_TOKEN=$NODE_TOKEN sh -
echo "K3s agent installed."

echo "Verifying container runtime..."
k3s crictl info | grep runtimeType

echo "Checking K3s embedded containerd socket..."
ls -l /run/k3s/containerd/containerd.sock

echo "Confirming system containerd socket is not used..."
ls -l /run/containerd/containerd.sock || echo "System containerd socket does not exist, as expected."

echo "Listing pods running on this worker node..."
k3s crictl ps
