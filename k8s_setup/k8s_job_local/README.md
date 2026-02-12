# **CREATE A JOB USING K3S**

A container that exits successfully should be a **Job**, not a **Deployment**. That is the correct and clean solution if your container is only meant to run once and exit (it behaves like a batch task, not like a long-running service). Deployments expect containers to run fforever!

A **Deployment** container exits immediately, so Kubernetes restarts it → **CrashLoopBackOff**. (There is nothing wrong with the YAML — it’s doing exactly what Deployments are supposed to do!).

The problem is simply:

```
Your workload = short-lived
Your object type = long-running
They don’t match.
```

---

# **Create a Job**

```bash
[root@lab-x38 ~]# mkdir ~/rock8-job
[root@lab-x38 ~]# cd ~/rocky8-job
[root@lab-x38 ~]# emacs Dockerfile
[root@lab-x38 ~]# cat Dockerfile
# Use official Rocky 8 image
FROM rockylinux:8

# Install bash (just in case)
RUN yum -y install bash && yum clean all

# Set working directory
WORKDIR /app

# Add a simple script
RUN echo -e '#!/bin/bash\n\necho "Hi from Rocky 8 container!"\ncat /etc/os-release' > hello.sh
RUN chmod +x hello.sh

# Set default command
CMD ["./hello.sh"]
```

Kubernetes never forces Jobs to run on the master unless there are no other nodes or you explicitly schedule them there. Kubernetes schedules pods on any node that is **Ready**. It picks the worker node if the master is tainted.

```bash
[root@lab-x38 ~]# nerdctl -n k8s.io build -t rocky8-demo:latest .
```

The `-n k8s.io` flag in `nerdctl` or `ctr` tells the tool to use the Kubernetes `containerd` namespace, which is where `k3s` (or any Kubernetes using `containerd`) keeps its images and containers, separate from the *default* `containerd` namespace.

Here’s why it matters:

1. `k3s` uses `containerd` internally for all pods.
2. `containerd` can have multiple namespaces to isolate workloads. Kubernetes pods run in the `k8s.io` namespace.
3. If you build/load an image without `-n k8s.io`, the image goes into `containerd`’s default namespace.
4. Kubernetes won’t see images in the default namespace — so pods will fail with **ImagePullBackOff**.

Using `-n k8s.io` ensures the image is in the same namespace that `k3s` uses, so your Job can run without pulling from Docker Hub.

---

Check it exists:

```bash
[root@lab-x38 ~]# nerdctl -n k8s.io images | grep rocky
rocky8-demo   latest   0de6ca232ee5   3 days ago   linux/amd64   230.7MB   77.29MB
```

---

# **Save the image to a tar**

In the current setup, we must do the `.tar → scp → ctr load` workflow. This is because:

* We build the image on `gw38`.
* Kubernetes schedules the job on `gw39` (the worker node).
* But `gw39`’s `containerd` has no copy of your image.
* There is no registry in your setup, so `k3s` cannot pull the image.
* Therefore, Kubernetes would give **ImagePullBackOff**.

```bash
[root@lab-x38 ~]# nerdctl -n k8s.io save -o rocky8-demo.tar rocky8-demo:latest
```

Copy the tar to the worker node (`gw39`):

```bash
[root@lab-x38 ~]# scp rocky8-demo.tar gw39:/tmp/
```

Load the image into `containerd` on `gw39`:

(On worker node `gw39`)

```bash
[root@lab-x39 ~]# ctr -n k8s.io images import /tmp/rocky8-demo.tar
[root@lab-x39 ~]# cd /tmp
[root@lab-x39 tmp]# ls
rocky8-demo.tar
[root@lab-x39 tmp]# ctr -n k8s.io images ls | grep rocky
docker.io/library/rocky8-demo:latest application/vnd.docker.distribution.manifest.v2+json sha256:0de6ca232ee52115054f7deeb478dcd750479c30f6ffc7e61502983e098a9c86 73.7 MiB linux/amd64 io.cri-containerd.image=managed 
```

Both nodes now have the image in the `k8s.io` namespace.

---

# **Why this is required**

Because:

* `containerd` image stores are per node
* Kubernetes does not sync images automatically
* Kubernetes only pulls images from a registry
* You don’t have a registry
* So local builds never propagate to other nodes

This is normal Kubernetes behavior.

---

Then we can verify if the pod is runnable:

```bash
[root@lab-x39 ~]# k3s crictl images | grep rocky
docker.io/library/rocky8-demo   latest   5950bc5bcb9b5   77.3MB
```

Kubernetes can run your Pod. (If it had appeared only in `ctr` and NOT in `crictl`, something would have been wrong.) Now `gw39` has the image available, and Kubernetes can run it.

---

# **Create the Job YAML**

Get back to `lab-x38` to create the Job YAML:

```bash
[root@lab-x38 ~]# cd rocky8-demo/
[root@lab-x38 rocky8-demo]# emacs rocky8-job.yaml
[root@lab-x38 rocky8-demo]# cat rocky8-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: rocky8-demo-job
spec:
  template:
    spec:
      containers:
      - name: rocky8-demo
        image: docker.io/library/rocky8-demo:latest
        imagePullPolicy: IfNotPresent
      restartPolicy: Never
  backoffLimit: 0
```

The entire Job YAML is **100% created and controlled by you**, the user. Kubernetes does not auto-generate your Job manifest. You write it, you define what image to run, what command to run, how many retries, etc.

---

# **Apply the Job**

```bash
[root@lab-x38 ~]# k3s kubectl apply -f rocky8-job.yaml
```

Here Kubernetes immediately tries to schedule and start the pod. `kubelet`/`containerd` tries to pull the image named in your YAML. If the node where it lands does not have the image, the pod will fail with **ImagePullBackOff**.

By pre-loading the image on all potential nodes (your worker node `gw39`, as before), Kubernetes can start the pod without failing.

---

# **What Kubernetes does NOT do**

* It does **not** create images.
* It does **not** distribute images across nodes.
* It does **not** invent your Job spec.
* It does **not** assume images exist locally unless you ensure that.

---

# **To see where the job landed:**

```bash
[root@lab-x38 ~]# k3s kubectl get pods -o wide
NAME                     READY   STATUS      RESTARTS   AGE   IP            NODE
rocky8-demo-job-7zzxc    0/1     Completed   0          22m   XX.YY.A.BC    lab-x39
```

We applied the Job, so now the Job has already run (or is running) on your cluster.

Check Jobs:

```bash
[root@lab-x38 ~]# k3s kubectl get jobs
NAME             STATUS     COMPLETIONS   DURATION   AGE
rocky8-demo-job  Complete   1/1           4s         26m
```

Check logs:

```bash
[root@lab-x38 ~]# k3s kubectl logs rocky8-demo-job-7zzxc
Hi from Rocky 8 container!
NAME="Rocky Linux"
VERSION="8.9 (Green Obsidian)"
ID="rocky"
ID_LIKE="rhel centos fedora"
VERSION_ID="8.9"
PLATFORM_ID="platform:el8"
PRETTY_NAME="Rocky Linux 8.9 (Green Obsidian)"
ANSI_COLOR="0;32"
LOGO="fedora-logo-icon"
CPE_NAME="cpe:/o:rocky:rocky:8:GA"
HOME_URL="https://rockylinux.org/"
BUG_REPORT_URL="https://bugs.rockylinux.org/"
SUPPORT_END="2029-05-31"
ROCKY_SUPPORT_PRODUCT="Rocky-Linux-8"
ROCKY_SUPPORT_PRODUCT_VERSION="8.9"
REDHAT_SUPPORT_PRODUCT="Rocky Linux"
REDHAT_SUPPORT_PRODUCT_VERSION="8.9"
```
