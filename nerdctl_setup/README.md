# nerdctl Installation Script (v2.2.0)

The script automates the installation of **nerdctl**, the containerd CLI, in two variants: **Minimal** and **Full**. Installations are done in `/usr/local/bin` and `/usr/local` respectively.

---

## Overview

`nerdctl` is a Docker-compatible CLI for containerd. It provides basic container management functionality and integrates seamlessly with modern container tools.

1. **Minimal Installation:** Installs only the `nerdctl` client binary. Just the CLI to interact with containerd.
2. **Full Installation:** Installs the complete set including `nerdctl`, `buildctl`, `buildkit`, `containerd`, and CNI networking plugins.

---

## Part 1: Minimal Installation

Suitable for running containers but cannot build images.
**Steps performed by the script:**

```bash
cd /usr/local/bin
sudo curl -L https://github.com/containerd/nerdctl/releases/download/v2.2.0/nerdctl-2.2.0-linux-amd64.tar.gz
tar -xvzf nerdctl.tar.gz
```

This will have installed `nerdctl`,  `containerd-rootless.sh`, and `containerd-rootless-setuptool.sh`. We can note that:

```bash
[root@thuner-gw38 bin]# nerdctl version
WARN[0000] unable to determine buildctl version          error="exec: \"buildctl\": executable file not found in $PATH"
Client:
 Version:	v2.2.0
 OS/Arch:	linux/amd64
 Git commit:	4eb4cbdb6b7ae82ab864a9829d1162a20eb61f81
 buildctl:
  Version:	

Server:
 containerd:
  Version:	1.7.24
  GitCommit:	88bf19b2105c8b17560993bee28a01ddc2f97182
 runc:
  Version:	1.2.2
  GitCommit:	v1.2.2-0-g7cb3632
```

Note that this warning means that nerdctl cannot find the buildctl binary in your system `$PATH`.

* nerdctl can work without buildctl for running containers and pulling/running images (Minimal installation includes only nerdctl).
* buildctl is required for building images (e.g., `nerdctl build` or Docker build equivalent).

---

## Part 2: Full Installation

The full installation provides all necessary binaries and components for a complete containerd development environment.

**Steps performed by the script:**

```bash
cd /usr/local/
sudo curl -L https://github.com/containerd/nerdctl/releases/download/v2.2.0/nerdctl-full-2.2.0-linux-amd64.tar.gz
tar xzvvf nerdctl-full.tar.gz
```

Which installs:

* `nerdctl` and `nerdctl.gomodjail`
* `buildctl`, `buildkitd`, `buildg`
* `containerd` and `containerd-shim-runc-v2`
* CNI networking plugins (`bridge`, `loopback`, `ipvlan`, etc.)
* Rootless scripts (`containerd-rootless.sh` and `containerd-rootless-setuptool.sh`)
* Helper binaries for overlay filesystems, stargz snapshots, and networking (`fuse-overlayfs`, `stargz-fuse-manager`, etc.)
* Systemd service files for `containerd`, `buildkit`, and stargz snapshotter

```bash
[root@thuner-gw38 local]# which buildctl
/usr/local/bin/buildctl
[root@thuner-gw38 local]# which nerdctl
/usr/local/bin/nerdctl
```

**Notes:**

* Full installation is recommended for developers who need **image building**, **multi-platform builds**, or complete containerd functionality.
* All binaries are installed under `/usr/local/bin` and libraries in `/usr/local/lib` and `/usr/local/libexec`.

---

## Full architecture and interaction between Docker CE, containerd, nerdctl, and buildctl

1. **Docker CE and containerd:**

   * When you install Docker CE on a Linux system: Docker CLI -> `dockerd` -> containerd (installed via the package `containerd.io`) as the container runtime that exposes the socket `/run/containerd/containerd.sock`.
   * The Docker CLI talks to `dockerd` (via `/var/run/docker.sock`), and Docker in turn talks to `containerd` (via `/run/containerd/containerd.sock`) to manage containers.
   * Docker CE includes BuildKit (`docker buildx` talks to it) internally and everything needed for buildctl functionality.

2. **Nerdctl:**

   * `nerdctl` is a Docker-compatible CLI for containerd, maintained independently. Talks directly to `containerd`, without a Docker daemon:

   ```bash
   nerdctl --address /run/containerd/containerd.sock info
   ```

   * Can run containers, build images, manage volumes, etc., in a way similar to Docker CLI.
   * Nerdctl can be installed side-by-side with Docker CE, even using a different containerd instance. It does not require Docker CE.

3. **Socket and path separation:**

   * Docker CE (with containerd.io) uses its own `containerd` instance via `/run/containerd/containerd.sock`.
   * `nerdctl` can use its own `containerd` instance (the full version includes the `containerd` binary) or you can point it to Docker CE’s `containerd` socket if desired via the command:

   ```bash
   nerdctl --address /run/containerd/containerd.sock ps
   ```

   * If you run `nerdctl` without `--address`, it defaults to `/run/containerd/containerd.sock`.

They are independent by default, but `nerdctl` can connect to the same `containerd` if you explicitly configure it. `nerdctl` is just a CLI client for `containerd`. `nerdctl` does not automatically start `containerd`. There is no socket created on installation (Full installation adds the containerd binary).

`containerd` is a daemon. To create the socket `/run/containerd/containerd.sock`, it must be started. If Docker CE is installed, Docker starts containerd for you. If `nerdctl` is installed alone, you must either start containerd manually or use rootless `containerd`.

---

## Summary

| Installation | Contents                                        | Recommended Use                                        |
| ------------ | ----------------------------------------------- | ------------------------------------------------------ |
| Minimal      | `nerdctl`, rootless scripts                     | Basic container management, running existing images    |
| Full         | All binaries, buildctl, containerd, CNI plugins | Full development, building images, advanced networking |

