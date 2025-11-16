# K3s Firewall / Networking Setup for Kubernetes Cluster

K3s nodes need to communicate for:

* Node registration and API access.
* Pod-to-pod networking across nodes.
* Metrics, logs, and health checks.
* Optional external access to services (NodePort).

A misconfigured firewall can break cluster functionality or pod networking.

---

## **Required Firewall Ports**

### **Master Node**

The master runs the API server, scheduler, controller manager, and embedded container runtime. It needs to accept connections from worker nodes and clients.

| Port        | Protocol | Purpose                                                                                           |
| ----------- | -------- | ------------------------------------------------------------------------------------------------- |
| 6443        | TCP      | Kubernetes API server (workers & `kubectl` clients connect here)                                  |
| 10250       | TCP      | Kubelet API (master communicates with workers / master talks to worker kubelets for metrics/logs) |
| 8472        | UDP      | Flannel VXLAN (pod network overlay)                                                               |
| 30000-32767 | TCP      | NodePort services (optional, only if exposing services externally)                                |

`30949/tcp` → K3s internal ephemeral ports, usually fine if already open. This kind of port is dynamically assigned by K3s for things like:

* Agent/server heartbeat communication
* Internal cluster components (for example, certain `containerd` or K3s internal services)
* Flannel or service proxies may occasionally use dynamic ports if fixed ports are busy

These are not standard Kubernetes ports, and K3s doesn’t document each one individually. We don’t need to open them unless your firewall is very restrictive and blocks all ephemeral outgoing ports.

---

### **Worker Nodes**

The worker runs `k3s-agent`, `kubelet`, `kube-proxy`, and `containerd`. It mainly needs outgoing access to the master and incoming access for pod networking.

| Port        | Protocol | Purpose                                                        |
| ----------- | -------- | -------------------------------------------------------------- |
| 10250       | TCP      | Kubelet API (master queries metrics/logs)                      |
| 8472        | UDP      | Flannel VXLAN (pod network overlay)                            |
| 30000-32767 | TCP      | NodePort services (optional, only if exposing pods externally) |

> **Note:** Workers initiate connections to the API server, so `6443/tcp` does not need to be open for incoming traffic. That is, workers do NOT need `6443/tcp` open for incoming traffic because they initiate connections to the master API server.

---

## How Workers Communicate with the API Server

* The K3s master runs the API server on port `6443/tcp`.
* Worker nodes (`k3s-agent`) need to communicate with this API server to:

  * Register themselves in the cluster
  * Report node status, pod status, and health
  * Receive pod scheduling instructions from the master

**Direction of traffic matters!**

* Workers do not need `6443/tcp` open for incoming connections.

  * Workers initiate outgoing TCP connections to the master on port `6443`.
  * Outgoing connections are usually allowed by default on most Linux firewalls.
* The master node must have `6443/tcp` open for incoming connections because that’s where workers and `kubectl` clients connect.

Diagram of connection:

```bash
Worker Node (`k3s-agent`)  ---->  TCP 6443  ---->  Master Node (API server)
         (outgoing)                       (incoming)
```

**Why workers don’t need `6443/tcp` open**

* TCP is connection-oriented. When a worker opens an outgoing connection to `6443/tcp` on the master, the return traffic automatically comes back.
* There is no need for the master to initiate a connection to the worker on `6443`.
* Firewalls on the worker only need to allow the outgoing traffic (usually allowed by default), so no inbound `6443/tcp` rule is necessary.

**What `6443` is for**

* Port `6443` on the master is the Kubernetes API server.
* All cluster-wide operations go through it:

  * `kubectl get nodes`
  * `kubectl apply -f pod.yaml`
  * Node registration
  * Pod scheduling instructions

Workers always connect to `6443` to get their instructions.
