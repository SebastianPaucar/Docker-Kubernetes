# K3s Cluster Deployment (Worker Node)

We need a previously running K3s **server/control-plane node** (master) with network access from the worker and Port **6443** open from worker → master (Kubernetes API server).

---

## **1. Verify Connectivity to Master**

On the worker node, check that the master node is reachable:

```bash
nc -zv <MASTER_NODE_HOSTNAME> 6443
```

Example:

```bash
[root@lab-x39 ~]# nc -zv lab-x38 6443
Ncat: Version 7.92 ( https://nmap.org/ncat )
Ncat: Connected to XXX.YYY.ZZZ.AB:6443.
Ncat: 0 bytes sent, 0 bytes received in 0.03 seconds.
```

* `Connected` output confirms network access.

---

## **2. Get the Node Token from the Master**

On the master node, retrieve the node token:

```bash
cat /var/lib/rancher/k3s/server/node-token
```

* Copy this token (let’s say `<NODE_TOKEN>`); it will be used to authenticate the worker node.

---

## **3. Install K3s Agent on the Worker Node**

Run the following on the worker node:

```bash
curl -sfL https://get.k3s.io | K3S_URL=https://<MASTER_NODE_HOSTNAME>:6443 K3S_TOKEN=<NODE_TOKEN> sh -
```

Example:

```bash
curl -sfL https://get.k3s.io | K3S_URL=https://lab-x38:6443 K3S_TOKEN=K1…401 sh -
```

* This installs **k3s in agent mode**, connecting it to the master.

---

## **4. Verify Container Runtime**

Check that the container runtime is running correctly:

```bash
[root@lab-x39 ~]# k3s crictl info | grep runtimeType
          "runtimeType": "io.containerd.runc.v2",
          "runtimeType": "io.containerd.runhcs.v1",
```

This output comes from `k3s crictl info`, which queries the container runtime interface (CRI). `io.containerd.runc.v2` is the default Linux runtime (`runc`) for containers. K3s on Linux will still use `runc.v2` for all your pods. The `runc.v2` entry is the one actually being used for your Linux containers. The worker node is correctly using `containerd` as its runtime!

---

## **5. Verify the Worker Node Joined the Cluster**

On the master node:

```bash
k3s kubectl get nodes
```

* The new worker should appear as `Ready`:

```
[root@lab-x38 ~]# k3s kubectl get nodes
NAME        STATUS   ROLES                  AGE     VERSION
lab-x38   Ready    control-plane,master   4d23h   v1.33.5+k3s1
lab-x39   Ready    <none>                 4d23h   v1.33.5+k3s1
```

---

## Worker Nodes Don’t Run the API Server

* In Kubernetes (and K3s), there is a control plane and worker nodes.
* All `kubectl` or `k3s kubectl` commands that query cluster-wide information should be run on the master node. Worker nodes don’t run the API server.

**Control plane / master node** runs:

* API server (`kube-apiserver`) → the central point for all Kubernetes commands and cluster state.
* Scheduler → decides where pods go.
* Controller manager → handles replication, scaling, etc.
* etcd (in K3s it’s embedded or SQLite by default)

**Worker nodes** run:

* `kubelet` / `k3s-agent` → communicates with the API server.
* Container runtime (`containerd`) → runs the actual pods/containers.
* `kube-proxy` → handles networking rules

Implication:

* Any command like `kubectl get nodes` or `kubectl get pods -A` queries the API server.
* Worker nodes don’t run an API server themselves, so if you run `kubectl` on the worker without pointing it to the master, it won’t have full cluster information.
* You can run `kubectl` on a worker if you use the kubeconfig from the master and point to the API server.

---

## What Can You Do from a Worker Node?

From the worker node itself, you can:

* Run and manage containers/pods scheduled to that node.
* Inspect the local container runtime with `crictl` (like you did).
* Check logs of pods running on that node (`k3s crictl ps`, `k3s crictl logs <container_id>`).
* Start or stop the `k3s-agent` service.

You cannot:

* Schedule new pods cluster-wide directly.
* Query cluster-wide state unless pointing to the master.

---

## The Worker Node Uses `containerd` as Its Container Runtime by Default

* K3s uses `containerd` to actually run containers on nodes (worker or master).
* `containerd` is a lightweight daemon that manages images, containers, snapshots, and storage.
* Each pod on the worker node runs as one or more `containerd` containers.

Why it’s needed:

* Even if the worker node doesn’t run the API server, it still needs to run pods.
* `containerd` is what actually executes the pod workloads.
* Without `containerd`, the worker node can’t run any Kubernetes workloads.

**K3s installs its own `containerd` instance**. When you install `k3s-agent` (for the worker node setup), it comes with an embedded `containerd`. This is separate from any system Docker or `nerdctl`/`containerd` installation you may have!

```bash
[root@lab-x39 ~]# ls -l /run/k3s/containerd/containerd.sock
srw-rw----. 1 root root 0 Nov 10 19:43 /run/k3s/containerd/containerd.sock
```

* K3s uses this embedded `containerd` to run all pods scheduled to the nodes.
* `k3s crictl` automatically points to this socket:

```bash
[root@lab-x39 ~]# k3s crictl info | grep runtimeType
          "runtimeType": "io.containerd.runc.v2",
[root@lab-x39 ~]# ls -l /run/containerd/containerd.sock
ls: cannot access '/run/containerd/containerd.sock': No such file or directory
```

That means the K3s worker is using the K3s `containerd`.

* By default, `k3s-agent` does NOT use system `containerd` or `nerdctl` — it exclusively uses its embedded one.

---

## Can You Build Images on a Worker Node?

* `k3s-agent` does not include Docker or a full build system by default.
* `containerd` can store and run images, but it does not provide an image-building CLI like `docker build`.
* So if you want to build container images on a worker, you need:

  * Docker installed, or
  * `nerdctl` (the `containerd` client for building images), or
  * Build images elsewhere and push them to a registry.

---

## `crictl` vs `ctr`: What’s the difference?

### `crictl`:

`crictl` is the Kubernetes-facing tool. It talks to the CRI (Container Runtime Interface): the API layer that Kubernetes uses to manage containers!

#### **What it is for:**

* Checking pods and containers that Kubernetes created.
* Debugging kubelet → container runtime issues.
* Pulling images *as Kubernetes would do*.
* Seeing the sandboxes (pods) and containers controlled by kubelet.

In k3s, `crictl` talks to `/run/k3s/containerd/containerd.sock` (NOT the raw containerd socket). This socket exposes only the CRI API, not all containerd features! Some examples are:

```bash
[root@lab-x39 ~]# k3s crictl ps
CONTAINER           IMAGE               CREATED             STATE               NAME                ATTEMPT             POD ID              POD                            NAMESPACE
637f11e8fa2eb       f7415d0003cb6       10 days ago         Running             lb-tcp-443          0                   28520b4a9a252       svclb-traefik-57d0a611-2xlrg   kube-system
3674cac23a7a9       f7415d0003cb6       10 days ago         Running             lb-tcp-80           0                   28520b4a9a252       svclb-traefik-57d0a611-2xlrg   kube-system
[root@lab-x39 ~]# k3s crictl images
IMAGE                              TAG                 IMAGE ID            SIZE
docker.io/library/rocky8-demo      latest              5950bc5bcb9b5       77.3MB
docker.io/rancher/mirrored-pause   3.6                 6270bb605e12e       301kB
<none>                             <none>              ee29d6321116a       77.3MB
docker.io/rancher/klipper-lb       v0.4.13             f7415d0003cb6       5.02MB
```

This  shows **exactly what kubelet sees**! Use  to check if Kubernetes actually sees the image! Correct command:

```bash
k3s crictl images | grep rocky
```

### `ctr`

**ctr is the low-level containerd CLI**. It talks directly to containerd’s internal APIs.

#### **What it is for:**

* Debugging containerd itself.
* Managing images manually.
* Loading images (`ctr images import`).
* Inspecting namespaces (`ctr -n k8s.io`).
* Working with snapshots.

In k3s, `ctr` connects to `/run/k3s/containerd/containerd.sock`, but **you must specify the namespace**:

* Kubernetes uses the namespace → `k8s.io`
* Nerdctl uses → `default`
* System containers may use → `containerd.io`

For loading images in k3s, we should use `ctr` because `crictl` *cannot import images*. Correct command for this:

```bash
k3s ctr -n k8s.io images import rocky8-demo.tar
```

Some examples are:

```bash
[root@lab-x39 ~]# k3s ctr -n k8s.io images ls
REF                                                                                                      TYPE                                                      DIGEST                                                                  SIZE      PLATFORMS                                                      LABELS                          
docker.io/library/rocky8-demo:latest                                                                     application/vnd.docker.distribution.manifest.v2+json      sha256:0de6ca232ee52115054f7deeb478dcd750479c30f6ffc7e61502983e098a9c86 73.7 MiB  linux/amd64                                                    io.cri-containerd.image=managed 
docker.io/rancher/klipper-lb:v0.4.13                                                                     application/vnd.oci.image.index.v1+json                   sha256:7eb86d5b908ec6ddd9796253d8cc2f43df99420fc8b8a18452a94dc56f86aca0 4.8 MiB   linux/amd64,linux/arm/v7,linux/arm64                           io.cri-containerd.image=managed 
docker.io/rancher/klipper-lb@sha256:7eb86d5b908ec6ddd9796253d8cc2f43df99420fc8b8a18452a94dc56f86aca0     application/vnd.oci.image.index.v1+json                   sha256:7eb86d5b908ec6ddd9796253d8cc2f43df99420fc8b8a18452a94dc56f86aca0 4.8 MiB   linux/amd64,linux/arm/v7,linux/arm64                           io.cri-containerd.image=managed 
docker.io/rancher/mirrored-pause:3.6                                                                     application/vnd.docker.distribution.manifest.list.v2+json sha256:74c4244427b7312c5b901fe0f67cbc53683d06f4f24c6faee65d4182bf0fa893 294.4 KiB linux/amd64,linux/arm/v7,linux/arm64,linux/s390x,windows/amd64 io.cri-containerd.image=managed 
docker.io/rancher/mirrored-pause@sha256:74c4244427b7312c5b901fe0f67cbc53683d06f4f24c6faee65d4182bf0fa893 application/vnd.docker.distribution.manifest.list.v2+json sha256:74c4244427b7312c5b901fe0f67cbc53683d06f4f24c6faee65d4182bf0fa893 294.4 KiB linux/amd64,linux/arm/v7,linux/arm64,linux/s390x,windows/amd64 io.cri-containerd.image=managed 
sha256:5950bc5bcb9b563f5d4c3c529042a212330b9b328fcbd7f8dbdcf6c25caa7ee8                                  application/vnd.docker.distribution.manifest.v2+json      sha256:0de6ca232ee52115054f7deeb478dcd750479c30f6ffc7e61502983e098a9c86 73.7 MiB  linux/amd64                                                    io.cri-containerd.image=managed 
sha256:6270bb605e12e581514ada5fd5b3216f727db55dc87d5889c790e4c760683fee                                  application/vnd.docker.distribution.manifest.list.v2+json sha256:74c4244427b7312c5b901fe0f67cbc53683d06f4f24c6faee65d4182bf0fa893 294.4 KiB linux/amd64,linux/arm/v7,linux/arm64,linux/s390x,windows/amd64 io.cri-containerd.image=managed 
sha256:ee29d6321116af48cf9ecf604947c5d3638a2fd9c6cb8443543612c9184893e0                                  application/vnd.docker.distribution.manifest.v2+json      sha256:2206366b7eb2a2483e00527f4a0bedbb29a289b1ef800c746bc035f341eaff31 73.7 MiB  linux/amd64                                                    io.cri-containerd.image=managed 
sha256:f7415d0003cb62ded390ed491fc842ee821878a04cc137196c21c1050101dd5e                                  application/vnd.oci.image.index.v1+json                   sha256:7eb86d5b908ec6ddd9796253d8cc2f43df99420fc8b8a18452a94dc56f86aca0 4.8 MiB   linux/amd64,linux/arm/v7,linux/arm64                           io.cri-containerd.image=managed 
[root@lab-x39 ~]# k3s ctr -n k8s.io containers ls
CONTAINER                                                           IMAGE                                   RUNTIME                  
28520b4a9a252d5036e2acfa2567e9892c145cdb1628c8e63f59b63ec76ae185    docker.io/rancher/mirrored-pause:3.6    io.containerd.runc.v2    
3674cac23a7a93be3dc1731718d54c0cce68bbd430f18fc1f20dc5cf448a701b    docker.io/rancher/klipper-lb:v0.4.13    io.containerd.runc.v2    
5b539160ecbde9537767ee38accf51b1b493eead5458c6ef06f6a8792970bcf1    docker.io/rancher/mirrored-pause:3.6    io.containerd.runc.v2    
61f818b4a5411ecf429ef81445233f887eb27e907f9394b215981237aaaf9e30    docker.io/library/rocky8-demo:latest    io.containerd.runc.v2    
637f11e8fa2ebb1f29353e9400bb94616c46621a857ff27787be8e1054c4a1d9    docker.io/rancher/klipper-lb:v0.4.13    io.containerd.runc.v2    
```

---

### Big Differences


| Feature             | crictl                     | ctr                                   |
| ------------------- | -------------------------- | ------------------------------------- |
| API Level           | High (CRI)                 | Low (containerd internal)             |
| Scope               | Only Kubernetes containers | Everything in containerd              |
| Socket              | CRI socket                 | containerd socket                     |
| Namespace awareness | No                         | Requires `-n k8s.io`                  |
| Image import        | No                         | Yes (`ctr images import`)           |
| Ideal for           | K8s debugging              | Containerd debugging / loading images |

* **crictl = what Kubernetes sees**
* **ctr = what containerd sees**
* Kubernetes jobs/pods only see images in:
  → `ctr -n k8s.io`

