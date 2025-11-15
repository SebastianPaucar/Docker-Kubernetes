#!/bin/bash
set -euo pipefail

NERDCTL_ROOT="/var/lib/containerd-nerdctl"
NERDCTL_RUN="/run/containerd-nerdctl"
NERDCTL_ETC="/etc/containerd-nerdctl"
NERDCTL_SOCKET="$NERDCTL_RUN/containerd.sock"

PREEXISTING_CONFIG="/root/config.toml"
PREEXISTING_SERVICE="/root/containerd-nerdctl.service"

echo "Stopping and disabling system containerd..."
systemctl stop containerd
systemctl disable containerd
systemctl mask containerd

echo "Removing old system containerd sockets..."
rm -f /run/containerd/containerd.sock /run/containerd/containerd.sock.ttrpc

echo "Creating nerdctl directories..."
mkdir -p "$NERDCTL_ETC" "$NERDCTL_RUN" "$NERDCTL_ROOT"/{overlayfs,blockfile,btrfs,devmapper,erofs,native,zfs}

echo "Setting ownership and permissions..."
chown -R root:root "$NERDCTL_ROOT" "$NERDCTL_RUN"
chmod 755 "$NERDCTL_ROOT" "$NERDCTL_RUN"

echo "Copying pre-existing nerdctl config and systemd service..."
cp "$PREEXISTING_CONFIG" "$NERDCTL_ETC/config.toml"
cp "$PREEXISTING_SERVICE" "/etc/systemd/system/containerd-nerdctl.service"

echo "Reloading systemd and starting nerdctl containerd..."
systemctl daemon-reload
systemctl enable --now containerd-nerdctl

echo "Restoring system containerd and Docker..."
systemctl unmask containerd
systemctl enable --now containerd
systemctl enable --now docker

echo "Running a test nginx container with nerdctl..."
nerdctl --address="$NERDCTL_SOCKET" run -d --name test-nginx -p 8080:80 nginx:alpine

echo "Listing nerdctl containers..."
nerdctl --address="$NERDCTL_SOCKET" ps

echo "Setup completed!"
