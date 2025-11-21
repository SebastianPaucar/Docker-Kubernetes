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
[root@thuner-gw39 ~]# nc -zv thuner-gw38 6443
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
curl -sfL https://get.k3s.io | K3S_URL=https://thuner-gw38:6443 K3S_TOKEN=K1…401 sh -
```

* This installs **k3s in agent mode**, connecting it to the master.

---

## **4. Verify Container Runtime**

Check that the container runtime is running correctly:

```bash
[root@thuner-gw39 ~]# k3s crictl info | grep runtimeType
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
[root@thuner-gw38 ~]# k3s kubectl get nodes
NAME        STATUS   ROLES                  AGE     VERSION
thuner-gw38   Ready    control-plane,master   4d23h   v1.33.5+k3s1
thuner-gw39   Ready    <none>                 4d23h   v1.33.5+k3s1
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
[root@thuner-gw39 ~]# ls -l /run/k3s/containerd/containerd.sock
srw-rw----. 1 root root 0 Nov 10 19:43 /run/k3s/containerd/containerd.sock
```

* K3s uses this embedded `containerd` to run all pods scheduled to the nodes.
* `k3s crictl` automatically points to this socket:

```bash
[root@thuner-gw39 ~]# k3s crictl info | grep runtimeType
          "runtimeType": "io.containerd.runc.v2",
[root@thuner-gw39 ~]# ls -l /run/containerd/containerd.sock
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
k3s crictl ps
k3s crictl images
k3s crictl inspect <container>
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
k3s ctr -n k8s.io images ls
k3s ctr -n k8s.io containers ls
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

