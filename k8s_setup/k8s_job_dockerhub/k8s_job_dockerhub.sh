#!/bin/bash

set -euo pipefail

# Variables
NAMESPACE="k8s.io"
IMAGE_NAME="sebastianpaucar/rocky8-test-docker-hub"
TAG="latest"
DOCKERFILE="/root/rocky8-demo/Dockerfile"
BUILD_CONTEXT="/root/rocky8-demo"
JOB_YAML="rocky8-job-docker-hub.yaml"

# Step 1: Build the image in containerd (k8s.io namespace)
echo "Building image..."
nerdctl -n "$NAMESPACE" build -t "$IMAGE_NAME:$TAG" -f "$DOCKERFILE" "$BUILD_CONTEXT"

# Step 2: Login to Docker Hub (prompt for username and PAT)
echo "Logging in to Docker Hub..."
nerdctl logout docker.io || true
nerdctl login docker.io

# Step 3: Push the image to Docker Hub
echo "Pushing image to Docker Hub..."
nohup nerdctl -n "$NAMESPACE" push "$IMAGE_NAME:$TAG" > push_command.out 2>&1 &

# Wait for the push to complete
wait
echo "Image push completed. Check push_command.out for details."

# Step 4: Remove the local image (optional, for testing Kubernetes pull)
echo "Removing local image..."
nerdctl -n "$NAMESPACE" rmi "$IMAGE_NAME:$TAG"

# Step 5: Apply Kubernetes Job
echo "Applying Kubernetes Job..."
k3s kubectl apply -f "$JOB_YAML"

# Step 6: Show pod status
echo "Kubernetes Job applied. Checking pod status..."
k3s kubectl get pods -o wide

echo "Script completed successfully."
