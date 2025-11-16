#!/bin/bash

set -euo pipefail

echo "Starting firewall configuration for K3s MASTER node..."

echo "Opening Kubernetes API server port 6443/tcp..."
sudo firewall-cmd --permanent --add-port=6443/tcp

echo "Opening Kubelet API port 10250/tcp..."
sudo firewall-cmd --permanent --add-port=10250/tcp

echo "Opening Flannel VXLAN port 8472/udp for pod networking..."
sudo firewall-cmd --permanent --add-port=8472/udp

echo "Reloading firewall to apply changes..."
sudo firewall-cmd --reload

echo "Firewall configuration complete for MASTER node."
echo "Currently open ports:"
sudo firewall-cmd --list-ports
