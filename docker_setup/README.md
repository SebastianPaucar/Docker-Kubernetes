# Docker CE Installation via DNF

## Overview

The script performs a deterministic, non-interactive installation of **Docker CE**, its associated client utilities, the **containerd** runtime, and Buildx/Compose plugins. It relies on the official *docker-ce-stable* YUM repository.

---

## What the Script Does

### 1. Register the Docker CE RPM Repository

```bash
sudo dnf config-manager --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo
```

Although labeled *centos*, this repo provides EL9-compatible packages for AlmaLinux 9.

* `dnf` is the package manager for CentOS/RHEL 8 and 9.
* `config-manager` is a plugin for `dnf` that allows managing repositories (add/enable/disable/modify repos).
* `--add-repo <URL>` tells `dnf config-manager` to add a new repository to the system.
* The official Docker CE repo provides Docker packages (`docker-ce`, `docker-ce-cli`, `containerd`, etc.) that are not in the default OS repositories. AlmaLinux does not ship the latest Docker CE packages in its official repos. This repo allows `dnf` to install *official, up-to-date* Docker packages directly from Docker later.

`dnf` fetches the `docker-ce.repo` file from the URL and stores it in `/etc/yum.repos.d/docker-ce.repo`. No packages are installed yet.

---

### 2. Install Specific Docker and containerd Builds

After fetching the repo, `dnf` knows about the Docker repo and *can* install Docker packages with `dnf install`:

* `containerd.io-1.7.24`
* `docker-ce-27.4.1`
* `docker-ce-cli-27.4.1`
* `docker-buildx-plugin-0.19.3`
* `docker-compose-plugin-2.32.1`
* `docker-ce-rootless-extras-27.4.1`

Pinning prevents uncoordinated upgrades and ensures deterministic binary compatibility across nodes.

---

### 3. Enable and Launch the Docker Daemon (dockerd)

```bash
sudo systemctl enable --now docker
```

This is a systemd command that manages services/daemons on modern Linux.

* `enable` does not start the service immediately; it just creates symbolic links in `/etc/systemd/system/multi-user.target.wants/` pointing to the service unit file.
* `--now` enables the service and starts it immediately in the current session. Without `--now`, `enable` only makes Docker start at boot. `systemctl start docker` would be required to start Docker right now.

The full command activates two systemd units:

```text
/usr/lib/systemd/system/docker.service
/usr/lib/systemd/system/docker.socket
```

#### **docker.service**

Without this, the Docker CLI (`docker run`, `docker ps`) would not be able to talk to a running daemon.

* This is the main service unit file.
* Invokes `/usr/bin/dockerd` (the Docker daemon) and controls it.
* Starts the Docker daemon in the background.
* Connects it to the host’s containerd instance:

```text
--containerd=/run/containerd/containerd.sock
```

#### **docker.socket**

* This is the systemd socket unit. It listens on a Unix socket (`/var/run/docker.sock`) for incoming Docker API requests from the CLI.
* Provides the activation socket for Docker’s API endpoint.
* Auto-starts `dockerd` on demand via socket-activation semantics.
* Auto-starts `docker.service` when a Docker command tries to connect.

This is called a **socket-activated service**. Systemd starts the service only when something connects to the socket. `docker.socket` and `docker.service` are enabled together by the Docker package. `systemctl enable --now docker` ensures both are active.

You can observe the running daemon via:

```bash
ps aux | grep dockerd
[root@lab-x50 ~]# ps aux | grep dockerd
root 1143 0.0 0.1 3484368 105556 ? Ssl May20 25:15 /usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
root 3551234 0.0 0.0 3876 2304 pts/0 S+ 16:36 0:00 grep --color=auto dockerd
```

---

### 4. `containerd.io`

Docker CE depends on `containerd.io` as follows:

* `docker-ce` is the full Docker platform (CLI + daemon + orchestration features). It provides user tools (`dockerd`: Docker daemon; `docker`: Docker CLI with commands like `docker run`, `docker build`, `docker compose`, etc.; integration with plugins) to build, run, and manage containers.
* `containerd.io` is the low-level container runtime that manages the core lifecycle of containers (pulling/storing images, creating/running containers, and networking/storage at the container level).
* `containerd.io` runs as a daemon (`containerd`) in the background and does all the heavy lifting for Docker. Docker CE (`dockerd`) calls `containerd` to handle container lifecycle operations. Without `containerd`, Docker cannot actually run containers.

The workflow is:

```
docker-ce CLI (user commands) 
   -> dockerd daemon (orchestrates containers, talks to containerd) 
      -> containerd daemon (actual container runtime) 
         -> runc / low-level container process (launches processes inside containers)
```

`docker-ce` depends on `containerd.io`, but `containerd.io` can also be used independently by other systems like Kubernetes or `nerdctl` without Docker.

---

### 5. Validate Runtime Functionality

A `hello-world` execution confirms the full client–daemon–runtime pipeline:

```bash
docker run --rm hello-world
```

Steps:

1. `docker` CLI contacts `dockerd`.
2. `run` creates and starts a container.
3. `--rm` removes the container automatically after it exits.
4. `hello-world` is the image name. If not present locally, Docker will pull it from Docker Hub (`dockerd` pulls the image).

The CLI communicates with the Docker daemon through the socket `/var/run/docker.sock`. Docker then calls `containerd` to pull the image layers from Docker Hub, store them locally, prepare the container filesystem, and run the process via `runc`. This is why Docker must be running as a systemd service beforehand.

