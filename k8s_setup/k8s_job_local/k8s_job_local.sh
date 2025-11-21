#!/bin/bash

set -euo pipefail

JOB_DIR="$HOME/rocky8-job"
IMAGE_NAME="rocky8-demo:latest"
TAR_FILE="rocky8-demo.tar"
REMOTE_NODE="gw39"
REMOTE_PATH="/tmp"
JOB_YAML="rocky8-job.yaml"

echo "Creating job directory"
mkdir -p "$JOB_DIR"
cd "$JOB_DIR"

echo "Creating Dockerfile"
cat > Dockerfile <<EOF
FROM rockylinux:8
RUN yum -y install bash && yum clean all
WORKDIR /app
RUN echo -e '#!/bin/bash\necho Hi from Rocky 8\ncat /etc/os-release' > hello.sh
RUN chmod +x hello.sh
CMD ["./hello.sh"]
EOF

echo "Building image into k8s.io containerd namespace"
nerdctl -n k8s.io build -t "$IMAGE_NAME" .

echo "Saving image to tar file"
nerdctl -n k8s.io save -o "$TAR_FILE" "$IMAGE_NAME"

echo "Copying tar to worker node"
scp "$TAR_FILE" "$REMOTE_NODE:$REMOTE_PATH/"

echo "Importing image on worker node"
ssh "$REMOTE_NODE" "ctr -n k8s.io images import $REMOTE_PATH/$TAR_FILE"

echo "Verifying image on worker node"
ssh "$REMOTE_NODE" "ctr -n k8s.io images ls | grep rocky"

echo "Creating Job YAML"
cat > "$JOB_YAML" <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: rocky8-demo-job
spec:
  template:
    spec:
      containers:
      - name: rocky8-demo
        image: $IMAGE_NAME
        imagePullPolicy: IfNotPresent
      restartPolicy: Never
  backoffLimit: 0
EOF

echo "Applying Job to Kubernetes"
k3s kubectl apply -f "$JOB_YAML"

echo "Job submitted"

echo "Getting pods"
k3s kubectl get pods -o wide

echo "Getting logs"
k3s kubectl logs -l job-name=rocky8-demo-job

