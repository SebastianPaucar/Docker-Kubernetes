# K3s Cluster Deployment (master node)

This document describes the installation, configuration, and validation steps for a **Kubernetes mini cluster** using **K3s**, focused on the master node.
The deployment consists of:

* **thuner-gw38** → *Control-plane / Master node*
* **thuner-gw39** → *Worker / Agent node*

The cluster uses **containerd (K3s-managed runtime)** for Kubernetes workloads.

---

# Install K3s Server (Control-Plane) on gw38

## Install K3s (master)

```bash
curl -sfL https://get.k3s.io | sh -
sudo systemctl enable --now k3s
systemctl status k3s
k3s kubectl get nodes
```

This downloads the k3s binary into /usr/local/bin/k3s (from the install script (get.k3s.io) and pipes it to sh), writes a systemd unit (/etc/systemd/system/k3s.service), and creates runtime directories under /var/lib/rancher/k3s/. This starts a k3s server process (control plane), which in turn spawns an internal containerd for pod workloads.

Files created:

```bash
[root@thuner-gw38 ~]# ls /usr/local/bin/k3s
/usr/local/bin/k3s
[root@thuner-gw38 ~]# ls /etc/systemd/system/k3s.service
/etc/systemd/system/k3s.service
[root@thuner-gw38 ~]# ls /var/lib/rancher/k3s/server/node-token
/var/lib/rancher/k3s/server/node-token
[root@thuner-gw38 ~]# ls /etc/rancher/k3s/k3s.yaml
/etc/rancher/k3s/k3s.yaml
[root@thuner-gw38 ~]# ls /run/k3s/containerd/
containerd.sock        io.containerd.grpc.v1.cri      io.containerd.sandbox.controller.v1.shim
containerd.sock.ttrpc  io.containerd.runtime.v2.task
[root@thuner-gw38 ~]# ls /var/lib/rancher/k3s/agent/etc/containerd/
config.toml
```

* `/usr/local/bin/k3s` — the k3s executable.
* `/etc/systemd/system/k3s.service` — systemd unit (you showed it).
* `/var/lib/rancher/k3s/server/node-token` — cluster join token (required for workers to join).
* `/etc/rancher/k3s/k3s.yaml` — admin kubeconfig for kubectl.
* `/run/k3s/containerd/` — k3s-managed containerd runtime and socket.
* `/var/lib/rancher/k3s/agent/etc/containerd/` or similar — k3s containerd config (location can vary by k3s version).

## Systemd service created on master

Created at `/etc/systemd/system/k3s.service`:

```ini
[root@thuner-gw38 system]# cat k3s.service
[Unit]
Description=Lightweight Kubernetes
Documentation=https://k3s.io
Wants=network-online.target
After=network-online.target

[Install]
WantedBy=multi-user.target

[Service]
Type=notify
EnvironmentFile=-/etc/default/%N
EnvironmentFile=-/etc/sysconfig/%N
EnvironmentFile=-/etc/systemd/system/k3s.service.env
KillMode=process
Delegate=yes
User=root
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/k3s \
    server \.
```

The `ExecStart=/usr/local/bin/k3s server` line means this node is a control-plane server. This starts the k3s control plane. Server mode runs the API server + controller manager + scheduler + embedded container runtime (containerd).

The block:

```bash
[Unit]
Description=Lightweight Kubernetes
Wants=network-online.target
After=network-online.target
```

means **do not start until the network is fully online**. K3s needs to bind the Kubernetes API on port 6443.

When k3s server starts, it initializes the Kubernetes control plane and starts an internal containerd with the socket `/run/k3s/containerd/containerd.sock`.

We must verify the Kubernetes API server (port 6443). To check that the API server is listening locally (it must run on the master node or from any node trying to reach it):

```bash
[root@thuner-gw38 ~]# ss -tulpn | grep 6443
tcp   LISTEN 0      4096               *:6443             *:*    users:(("k3s-server",pid=181873,fd=12))                 
```

This proves the K3s control-plane API server is running on gw38.

## kubectl / k3s kubectl

This should be run only on gw38 (the master node), unless the kubeconfig is exported. This is because only gw38 (master node/control plane) hosts the API server and the kubeconfig:

```bash
k3s kubectl get nodes
k3s kubectl get pods -A
kubectl cluster-info
kubectl get nodes -o wide
```

Output:

```bash
[root@thuner-gw38 ~]# k3s kubectl get nodes
NAME              STATUS   ROLES                  AGE     VERSION
thuner-gw38.cpp   Ready    control-plane,master   4d21h   v1.33.5+k3s1
thuner-gw39.cpp   Ready    <none>                 4d21h   v1.33.5+k3s1
```

That means gw38 is ready: kubelet on this node is healthy and connected. The `control-plane,master` role means this node runs:

* kube-apiserver
* kube-controller-manager
* kube-scheduler
* etcd (or SQLite for k3s)
* kubelet
* containerd
* Traefik ingress
* CNI (flannel)

So this is the brain of the entire cluster. Without it, the cluster dies.

gw39 shows it is Ready: the node is healthy.

* ROLES: `<none>` because worker nodes in Kubernetes default to having no special role labels.
* This node only runs workloads (pods).

```bash
[root@thuner-gw38 ~]# k3s kubectl get pods -A
NAMESPACE     NAME                                      READY   STATUS             RESTARTS         AGE
default       rocky8-demo-f85c4b8cf-nlcz8               0/1     CrashLoopBackOff   817 (3m2s ago)   2d21h
kube-system   coredns-64fd4b4794-rmcbl                  1/1     Running            0                4d21h
kube-system   helm-install-traefik-crd-795sm            0/1     Completed          0                4d21h
kube-system   helm-install-traefik-pzmwc                0/1     Completed          1                4d21h
kube-system   local-path-provisioner-774c6665dc-sc28n   1/1     Running            0                4d21h
kube-system   metrics-server-7bfffcd44-m2cj5            1/1     Running            0                4d21h
kube-system   svclb-traefik-57d0a611-2xlrg              2/2     Running            0                4d21h
kube-system   svclb-traefik-57d0a611-x2vvs              2/2     Running            0                4d21h
kube-system   traefik-c98fdf6fb-w9l9w                   1/1     Running            0                4d21h
```

That means we deployed a pod named rocky8-demo. It is crashing continuously (CrashLoopBackOff = the pod fails → restarts → fails → restarts), and 817 restarts means Kubernetes tried 817 times to revive it. Other important components (coredns, helm-install-traefik, svclb-traefik, local-path-provisioner, traefik, and metrics-server) are healthy. The control plane is highly healthy.

```bash
[root@thuner-gw38 ~]# kubectl cluster-info
Kubernetes control plane is running at https://127.0.0.1:6443
CoreDNS is running at https://127.0.0.1:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://127.0.0.1:6443/api/v1/namespaces/kube-system/services/https:metrics-server:https/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

This means the API server is listening on localhost:6443 on gw38, and the kubeconfig that k3s gives you points API requests to 127.0.0.1. kubectl connects to a local proxy that forwards to the real k3s API.

```bash
[root@thuner-gw38 ~]# kubectl get nodes -o wide
NAME                          STATUS   ROLES                  AGE     VERSION        INTERNAL-IP      EXTERNAL-IP   OS-IMAGE                      KERNEL-VERSION                 CONTAINER-RUNTIME
thuner-gw38.cpp   Ready    control-plane,master   4d21h   v1.33.5+k3s1   XXX.YYY.ZZZ.AB   <none>        AlmaLinux 9.5 (Teal Serval)   5.14.0-503.11.1.el9_5.x86_64   containerd://2.1.4-k3s1
thuner-gw39   Ready    <none>                 4d21h   v1.33.5+k3s1   XXX.YYY.ZZZ.AB   <none>        AlmaLinux 9.5 (Teal Serval)   5.14.0-503.11.1.el9_5.x86_64   containerd://2.1.4-k3s1
```

This confirms gw38 master node IP, gw39 worker node IP, the OS, the kernel, and the runtime.

```bash
[root@thuner-gw38 ~]# cat /var/lib/rancher/k3s/server/node-token
K10a9c….1
```

This is one of the most important secrets in your entire K3s cluster. This file contains the cluster join token. It is automatically generated when you install k3s server (the master). All worker nodes MUST present this token to join the cluster. This string has three parts:

```bash
K1<big-random-secret> :: server : <server-id>
```

The `<big-random-secret>` is the actual cluster secret. It is used to authenticate worker nodes joining the cluster and establish trust between agents and the control plane. It is functionally equivalent to a password for joining the cluster.

* `server`: indicates the role that a joining node must take when using this token. It means the token is for joining as a server (control-plane), but in K3s, the same token is also used for agents (K3s uses a unified token).
* `<server-id>` is the Node ID (server identifier) of the master node. It uniquely identifies the control-plane instance (IP and port 6443). Workers use this ID to confirm they are talking to the correct server.

## K3s containerd dedicated-socket

This socket is created by the embedded containerd that k3s runs internally:

```bash
[root@thuner-gw38 ~]# ls  /var/run/k3s/containerd/
containerd.sock        io.containerd.grpc.v1.cri      io.containerd.sandbox.controller.v1.shim
containerd.sock.ttrpc  io.containerd.runtime.v2.task
```

It is ALWAYS present if k3s is running. Note that K3s uses the Kubernetes API server, not a `k3s.sock` socket. The Kubernetes API serverlistens on TCP port 6443, not on a Unix socket!

```bash
TCP/6443 → Kubernetes API server
```

There is no file like:

```bash
/var/run/k3s/k3s.sock
```

because k3s does not expose an API over a Unix socket. Note that the architecture of k3s is:

```bash
k3s binary
├── supervises embedded containerd
├── supervises kube-apiserver (TCP/6443)
├── supervises kubelet
├── supervises scheduler
└── supervises controller-manager
```

So the correct sockets are:

* **Kubernetes API**: `tcp://127.0.0.1:6443`
* **k3s internal containerd**: `/run/k3s/containerd/containerd.sock`

The systemd containerd and nerdctl-containerd is completely separate from the k3s-internal containerd.

When k3s runs in server mode, it launches its own private containerd instance instead of using the system one! This private containerd runs sandboxed under:

```bash
/run/k3s/containerd/
```

and exposes its CRI endpoint at:

```bash
/run/k3s/containerd/containerd.sock
```

This is the runtime used by all Pods, Deployments, and Kubernetes workloads inside the k3s cluster.
* Docker does NOT touch this containerd.
* System containerd does NOT touch this one.
* `nerdctl` does NOT touch this one.
* Only k3s uses this embedded runtime.

```bash
[root@thuner-gw38 ~]# ls -l /var/run/docker.sock
srw-rw----. 1 root docker 0 Nov  9 15:49 /var/run/docker.sock
[root@thuner-gw38 ~]# ls -l /run/containerd/containerd.sock
srw-rw----. 1 root root 0 Nov 14 18:10 /run/containerd/containerd.sock
[root@thuner-gw38 ~]# ls -l /run/containerd-nerdctl/containerd.sock
srw-rw----. 1 root root 0 Nov 14 18:05 /run/containerd-nerdctl/containerd.sock
[root@thuner-gw38 ~]# ls -l /run/k3s/containerd/containerd.sock
srw-rw----. 1 root root 0 Nov 10 19:34 /run/k3s/containerd/containerd.sock
```