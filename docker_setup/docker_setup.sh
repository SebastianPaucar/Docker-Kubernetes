#!/bin/bash
set -euo pipefail

echo "Adding Docker CE repository"
sudo dnf config-manager --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo

echo "Displaying docker-ce.repo contents"
cat /etc/yum.repos.d/docker-ce.repo

echo "Verifying that Docker repository is enabled"
if ! dnf repolist | grep -i docker >/dev/null 2>&1; then
    echo "Docker repository not detected"
    exit 1
fi

echo "Installing Docker CE and related components"
sudo dnf install -y \
  containerd.io-1.7.24-3.1.el9.x86_64 \
  docker-buildx-plugin-0.19.3-1.el9.x86_64 \
  docker-ce-cli-27.4.1-1.el9.x86_64 \
  docker-ce-27.4.1-1.el9.x86_64 \
  docker-ce-rootless-extras-27.4.1-1.el9.x86_64 \
  docker-compose-plugin-2.32.1-1.el9.x86_64

echo "Enabling and starting the Docker service"
sudo systemctl enable --now docker

echo "Checking Docker service status"
sudo systemctl status docker --no-pager

echo "Running hello-world for validation"
if ! docker run --rm hello-world; then
    echo "hello-world test failed"
    exit 1
fi

echo "Displaying Docker CE package metadata"
dnf info docker-ce

echo "Displaying containerd package metadata"
dnf info containerd.io

echo "Showing installed component versions"
docker --version
containerd --version
docker buildx version || echo "Buildx not found"
docker compose version || echo "Compose not found"

echo "Docker CE installation completed successfully"

