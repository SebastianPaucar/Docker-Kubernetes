#!/bin/bash
set -euo pipefail

echo "Installing K3s..."
curl -sfL https://get.k3s.io | sh -

echo "Enabling and starting k3s service..."
sudo systemctl enable --now k3s

echo "Checking k3s service status..."
systemctl status k3s

echo "Getting cluster nodes..."
k3s kubectl get nodes

echo "K3s installation and verification completed."
