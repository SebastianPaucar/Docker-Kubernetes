# Building, Pushing, and Running a Container Image with `nerdctl` and Docker Hub in K8s

This README explains the end-to-end process of building a container image for Rocky Linux 8 using nerdctl in a Kubernetes (k8s.io) namespace, pushing it to Docker Hub, and running it as a Kubernetes Job.
---

## Build the Image (Kubernetes Namespace)

```bash
[root@thuner-gw38 rocky8-demo]# pwd
/root/rocky8-demo
[root@thuner-gw38 rocky8-demo]# nerdctl -n k8s.io build -t sebastianpaucar/rocky8-test-docker-hub:latest -f /root/rocky8-demo/Dockerfile /root/rocky8-demo
[+] Building 4.6s (9/9)                                                                                                                    
 => [internal] load build definition from Dockerfile                                                                                  0.1s
[+] Building 4.7s (9/9) FINISHED                                                                                                           
 => [internal] load build definition from Dockerfile                                                                                  0.1s
 => => transferring dockerfile: 437B                                                                                                  0.0s
 => [internal] load metadata for docker.io/library/rockylinux:8                                                                       0.8s
 => [internal] load .dockerignore                                                                                                     0.1s
 => => transferring context: 2B                                                                                                       0.0s
 => [1/5] FROM docker.io/library/rockylinux:8@sha256:9794037624aaa6212aeada1d28861ef5e0a935adaf93e4ef79837119f2a2d04c                 0.1s
 => => resolve docker.io/library/rockylinux:8@sha256:9794037624aaa6212aeada1d28861ef5e0a935adaf93e4ef79837119f2a2d04c                 0.1s
 => CACHED [2/5] RUN yum -y install bash && yum clean all                                                                             0.0s
 => CACHED [3/5] WORKDIR /app                                                                                                         0.0s
 => CACHED [4/5] RUN echo -e '#!/bin/bash\n\necho "Hi from Rocky 8 container!"\ncat /etc/os-release' > hello.sh                       0.0s
 => CACHED [5/5] RUN chmod +x hello.sh                                                                                                0.0s
 => exporting to docker image format                                                                                                  1.8s
 => => exporting layers                                                                                                               0.0s
 => => exporting manifest sha256:0de6ca232ee52115054f7deeb478dcd750479c30f6ffc7e61502983e098a9c86                                     0.0s
 => => exporting config sha256:5950bc5bcb9b563f5d4c3c529042a212330b9b328fcbd7f8dbdcf6c25caa7ee8                                       0.0s) => => sending tarball                                                                                                                1.8s
Loaded image: docker.io/sebastianpaucar/rocky8-test-docker-hub:latest
```

* `-n k8s.io` ensures the image is visible to Kubernetes. Without it, the image exists only in containerd’s default namespace.
* `nerdctl build` uses BuildKit over containerd, not Docker Engine. The image is stored locally in containerd, not yet in Docker Hub.
* Kubernetes CRI (kubelet) and nerdctl must agree on the namespace to see the same images.
* The image is stored locally in containerd (BuildKit builds the image locally, using the local filesystem to execute Dockerfile instructions), not yet in Docker Hub.

That command does NOT use Docker Hub for storage. It builds the image locally and stores it in containerd, inside the k8s.io namespace. No push, no upload, no Docker Hub write happens at this step!

Note that this follows:

```bash
nerdctl -n [containerd-namespace] build \
  -t [registry/] [user-or-org]/[repository]:[tag] \
  -f [path-to-Dockerfile] \
  [build-context-directory]
```

The `-t` flag only assigns a name `sebastianpaucar/rocky8-test-docker-hub:latest`. This is just a label/tag, not a push! That part looks like a remote Docker Hub image, but at build time it is just “call this local image by this name”. This is the breakdown:

```bash
sebastianpaucar / rocky8-test-docker-hub : latest
│               │                        │
│               │                        └── tag
│               └── repository name
└── namespace / username (Docker Hub style)
```

This name does NOT cause a push. It is just a label on a local image. The name looks like Docker Hub, but it’s still local.

* No authentication to Docker Hub happens.
* No login needed.
* No PAT checked.
* No network write to Docker Hub.

---

## Docker Hub Authentication

Normally:

* `docker login` → just stores credentials
* `docker push` → checks repository permissions

But nerdctl is different. `nerdctl login` may eagerly validate repository scopes if:

* an image with a Docker Hub tag already exists locally
* containerd has pending push metadata
* previous auth state exists

On a first attempt:

```bash
[root@thuner-gw38 rocky8-demo]# nerdctl login docker.io
Enter Username: sebastianpaucar
Enter Password:
ERRO[0011] failed to call tryLoginWithRegHost            error="failed to call rh.Authorizer.Authorize: failed to fetch oauth token: unexpected status from GET request to https://auth.docker.io/token?offline_token=true&service=registry.docker.io: 401 Unauthorized" i=0
FATA[0000] failed to authorize: failed to fetch oauth token: unexpected status from GET request to https://auth.docker.io/token?scope=repository%3Asebastianpaucar%2Frocky8-test-docker-hub%3Apull&scope=repository%3Asebastianpaucar%2Frocky8-test-docker-hub%3Apull%2Cpush&service=registry.docker.io: 401 Unauthorized
```

This error looks like a login failure, but it is not actually a login failure. Nerdctl contacts Docker Hub’s auth service ([https://auth.docker.io/token](https://auth.docker.io/token)) and requests an OAuth token for `service=registry.docker.io`.

Docker Hub checks:

* username
* password or PAT (Personal Access Token)
* account status (rate limits, token validity)

Note that Docker Hub did not reject your credentials here. If credentials were wrong, you would have failed earlier. Login itself succeeded!

Right after storing credentials, nerdctl contacted `https://auth.docker.io/token` with the request:

```
scope=repository:sebastianpaucar/rocky8-test-docker-hub:pull
scope=repository:sebastianpaucar/rocky8-test-docker-hub:pull,push
service=registry.docker.io
```

This is not login — this is asking if I am allowed to pull/push this repository. Since the image already existed locally and was tagged as `docker.io/sebastianpaucar/rocky8-test-docker-hub:latest`, nerdctl tries to validate repo access, thinking: if this image exists, let's validate push rights now. Docker Hub answered `401 Unauthorized` (meaning it cannot issue a token for that repository with those scopes).

## The key distinction:

Docker Hub has two separate checks:

1. Authentication – “Is this user real? Are the credentials valid?”
2. Authorization – “Is this user allowed to pull/push this specific repository?”

You passed (1) but temporarily failed (2).

In my case, the 401 errors happened because I was using a Personal Access Token that only had read permissions, while nerdctl was requesting push (write) access. Pull is allowed by a read-only token, but push is not. Docker Hub responds `401 Unauthorized` in this case.

So now we have to log out to solve it.

---

# Why logout → login → push eventually worked

It was just a matter of switching to a full-access PAT (Read, Write, Delete) and then logging in again. Docker Hub could finally issue `scope=repository:...:pull,push`. Everything succeeded.

```bash
[root@thuner-gw38 rocky8-demo]# nerdctl logout docker.io
[root@thuner-gw38 rocky8-demo]# nerdctl login docker.io
Enter Username: sebastianpaucar
Enter Password: 
WARNING! Your credentials are stored unencrypted in '/root/.docker/config.json'.
Configure a credential helper to remove this warning. See
https://docs.docker.com/go/credential-store/
Login Succeeded
```

Now I am using this PAT:

```bash
Full Token SP Docker Hub
Scope: Read, Write, Delete
```

This token can:

* authenticate
* pull
* push
* delete

So when nerdctl did any of the following:

* basic login
* repo pre-authorization
* later push

Docker Hub could legally issue the requested OAuth token. It succeeded because the PAT includes Read + Write (+Delete) permissions.

---

# Docker credentials directory

All Docker-compatible authentication data is stored under `/root/.docker/` with the contents:

* `config.json`
* `.token_seed`
* `.token_seed.lock`

## `config.json`

```bash
[root@thuner-gw38 rocky8-demo]# cat /root/.docker/config.json
{
	"auths": {
		"https://index.docker.io/v1/": {
			"auth": "c2ViYXN0a..."
		}
	}
}
```

This file was created by `nerdctl login docker.io` and is used by `nerdctl`, `docker`, and `buildkit`. It stores registry credentials. The `auth` field contains the value `base64(username:PAT)` where:

* username = Docker Hub username
* PAT = Docker Hub Personal Access Token

So this file:

* Identifies who you are
* Does NOT push or pull images
* Is required before pull/push operations

## `.token_seed`

This file is used internally by `nerdctl`/`containerd`. It caches OAuth token seed data for Docker Hub and helps fetch short-lived registry tokens faster.

Important:

* Docker Hub does NOT use your PAT directly for pushes/pulls
* Your PAT is exchanged for temporary OAuth tokens
* `.token_seed.lock` prevents concurrent writes and is created automatically

---

## Local images in containerd

```bash
[root@thuner-gw38 rocky8-demo]# nerdctl -n k8s.io images
REPOSITORY                                TAG       IMAGE ID        CREATED           PLATFORM       SIZE       BLOB SIZE
sebastianpaucar/rocky8-test-docker-hub    latest    0de6ca232ee5    31 minutes ago    linux/amd64    230.7MB    77.29MB
rocky8-demo                               latest    0de6ca232ee5    5 days ago        linux/amd64    230.7MB    77.29MB
```

Note that `sebastianpaucar/rocky8-test-docker-hub` and `rocky8-demo` have the same IMAGE ID because they are the same image with two tags.

* IMAGE ID identifies the real image content
* REPOSITORY:TAG is just a label
*  Tagging does NOT duplicate images!

---

## Pushing an Image to Docker Hub with `nerdctl` (`containerd`/`k8s.io`)

```bash
[root@thuner-gw38 rocky8-demo]# nohup nerdctl -n k8s.io push docker.io/sebastianpaucar/rocky8-test-docker-hub:latest > push_command.out 2>&1 &
```

This command uploads a locally built image from containerd to Docker Hub.

At this point:

* The image already exists locally
* The user is already authenticated (`nerdctl login docker.io`)
* The image is stored in the k8s.io containerd namespace

The image is read from k8s.io (the same namespace used by Kubernetes). `push` uploads the image to the remote registry `docker.io/sebastianpaucar/rocky8-test-docker-hub:latest`, with:

* `docker.io` → Docker Hub registry
* `sebastianpaucar` → Docker Hub username
* `rocky8-test-docker-hub` → repository name
* `latest` → tag

The Docker Hub repository is created automatically at push time if it does not already exist, as long as your account/token has permission to create repositories.

Docker Hub processes this in four logical steps:

1. **Authentication**
   Docker Hub verifies:

* Your username
* Your PAT (Personal Access Token)
* That the PAT has write/push permission: If this fails → 401 Unauthorized!

2. **Repository existence check**

Docker Hub checks: Does repository `sebastianpaucar/rocky8-test-docker-hub` exist?

Two possible outcomes:

* Case A — Repo already exists: Docker Hub proceeds directly to upload layers
* Case B — Repo does NOT exist: Docker Hub auto-creates the repository

  * Only possible if:

    * Repo is under your own namespace
    * PAT has write/create permissions

This is what happened in our case.

3. **Layer upload (content-addressed)**

```bash
[root@thuner-gw38 rocky8-demo]# cat push_command.out
manifest-sha256:0de6ca232ee52115054f7deeb478dcd750479c30f6ffc7e61502983e098a9c86: done           |++++++++++++++++++++++++++++++++++++++| 
config-sha256:5950bc5bcb9b563f5d4c3c529042a212330b9b328fcbd7f8dbdcf6c25caa7ee8:   done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:6c04e6ab434a519ed87a9cac44a7618fc93a4cd7fc439f1525304279329ec610:    done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:9088cdb84e397c480d4c5f1675d1aa6928c3e8b5b30c57b68a756d5d1fda4d80:    done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:408baaf7656a04f11b3a489f39d93b0421cccf84ad6994ec766a0ac9ecfb00c8:    done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:e812b27cd8fb44e04efae5e2083b22e917ce5587be6b1ae16c82beae7dce34b3:    done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:8bdfd70ac8c6e4ba30ab09ba3e1a9084ef9a9eb05670f6ba55e7b967d55cb088:    done           |++++++++++++++++++++++++++++++++++++++| 
elapsed: 5.3 s                                                                    total:  73.7 M (13.9 MiB/s)
```

* Compares each layer SHA256
* Uploads only missing layers
* Skips existing ones

That’s why pushes are fast after the first time.

4. **Manifest push (final step)**

* The image manifest is uploaded
* The tag `latest` is attached
* The image becomes visible in Docker Hub UI

---

## Running a Kubernetes Job Using an Image from Docker Hub

The YAML file:

```bash
[root@thuner-gw38 rocky8-demo]# emacs rocky8-job-docker-hub.yaml
[root@thuner-gw38 rocky8-demo]# cat rocky8-job-docker-hub.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: rocky8-test-job-docker-hub
spec:
  template:
    spec:
      containers:
      - name: rocky8-demo
        image: docker.io/sebastianpaucar/rocky8-test-docker-hub:latest
        imagePullPolicy: Always
      restartPolicy: Never
  backoffLimit: 0
```

This file defines a Kubernetes Job, where a job:

* runs a container to completion
* is not restarted unless it fails
* is commonly used for batch or test workloads

Container definition:

```bash
containers:
- name: rocky8-demo
  image: docker.io/sebastianpaucar/rocky8-test-docker-hub:latest
  imagePullPolicy: Always
```

* `name`: container name inside the Pod
* `image`: Docker Hub image reference
* `imagePullPolicy: Always`:

  * Kubernetes always pulls the image
  * Even if it exists locally
  * Guarantees Docker Hub is used

This is subject to restart and retry behavior:

* Container is not restarted
* Job fails immediately on error
* No retries

---

## Removing the local image for testing:

```bash
[root@thuner-gw38 rocky8-demo]# nerdctl -n k8s.io rmi docker.io/sebastianpaucar/rocky8-test-docker-hub:latest
Untagged: docker.io/sebastianpaucar/rocky8-test-docker-hub:latest@sha256:0de6ca232ee52115054f7deeb478dcd750479c30f6ffc7e61502983e098a9c86
Deleted: sha256:c1827ee010dbe3d0e7aa85282da0a80f74f02da1c44d6e81313cccdf465e58c6
Deleted: sha256:a7e08d91226a25fe15865bb9932019d34f4aa84d08ba289cd731e75da706a7cf
Deleted: sha256:87dd7f00610340876bcda7f22a61bba2e0719090a0eb8c9646e38dd5776bf666
Deleted: sha256:79a520af1f360df73949a01b30ca1f08adf6e7581539e5483bfcb350a8fb621a
Deleted: sha256:a0893210e93bb7a674ffa8789d3ab3c8edcd55b2aa2201a42c078f823c3f5b90
```

This command:

* Removes the image from local containerd storage
* Deletes all associated layers if unused
* Guarantees Kubernetes cannot use a cached image

Verify the removal:

```bash
[root@thuner-gw38 rocky8-demo]# nerdctl -n k8s.io images
REPOSITORY     TAG       IMAGE ID        CREATED       PLATFORM       SIZE       BLOB SIZE
rocky8-demo    latest    0de6ca232ee5    5 days ago    linux/amd64    230.7MB    77.29MB
```

* Docker Hub image is gone locally
* Only the local tag `rocky8-demo:latest` remains
* Same IMAGE ID (content-addressed)

---

## Applying the Job:

```bash
[root@thuner-gw38 rocky8-demo]# k3s kubectl apply -f rocky8-job-docker-hub.yaml
job.batch/rocky8-test-job-docker-hub created
```

Kubernetes will:

1. Schedule a Pod
2. Ask containerd (k8s.io namespace) for the image
3. Image is missing locally
4. containerd pulls from `docker.io/sebastianpaucar/rocky8-test-docker-hub:latest`
5. Docker Hub serves the layers
6. Container starts
7. Job runs and exits

This proves:

* Docker Hub push succeeded
* Repository exists
* Image is pullable
* Credentials are valid (if private repo)
* Kubernetes is correctly integrated with containerd

Key conceptual point: Kubernetes never uses your build directory or Dockerfile. It only knows about:

* Image references
* Registries
* Pull policies

Final model:

```bash
Dockerfile → nerdctl build → local image
local image → nerdctl push → Docker Hub
Docker Hub → kubectl Job → Kubernetes Pod
```

---

## Verifying a Kubernetes Job Pulled and Ran an Image from Docker Hub

1. **Listing Pods**

```bash
[root@thuner-gw38 rocky8-demo]# k3s kubectl get pods -o wide
NAME                               READY   STATUS      RESTARTS   AGE   IP           NODE         NOMINATED NODE   READINESS GATES
rocky8-demo-job-7zzxc              0/1     Completed   0          2d    10.42.1.13   thuner-gw39   <none>           <none>
rocky8-test-job-docker-hub-k7r9q   0/1     Completed   0          93s   10.42.1.14   thuner-gw39   <none>           <none>
```

What this means:

* Each Job creates one Pod
* Pod names are auto-generated with a suffix (-k7r9q)
* STATUS: Completed means:

  * Container started
  * Ran successfully
  * Exited with code 0
* READY 0/1 is normal for Jobs

  * Container has already exited
  * Readiness is irrelevant for completed workloads

2. **Checking Job output (container logs)**

```bash
[root@thuner-gw38 rocky8-demo]# k3s kubectl logs rocky8-test-job-docker-hub-k7r9q
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

This confirms:  
* Container started  
* Script ran  
* Image contents are exactly what you built  
* Filesystem inside the Pod is from your image  

This is runtime confirmation, not metadata.  

3. **Verifying the image pull source**  

```bash
[root@thuner-gw38 rocky8-demo]# k3s kubectl describe pod rocky8-test-job-docker-hub-k7r9q | grep -i "Pulled"
Normal  Pulled     2m14s  kubelet  Successfully pulled image "docker.io/sebastianpaucar/rocky8-test-docker-hub:latest" in 932ms (932ms including waiting). Image size: 77285864 bytes.

```

This confirms three things at once:  
1. Image was not local → Kubernetes explicitly pulled it  
2. Registry used → `docker.io/sebastianpaucar/rocky8-test-docker-hub:latest`  
3. Pull performance → ~930 ms, ~77 MB, matches pushed layer sizes  

---

## End-to-end chain (fully verified):  

```bash
Dockerfile
↓
nerdctl build
↓
local image (containerd)
↓
nerdctl push
↓
Docker Hub repository
↓
Kubernetes Job
↓
containerd pull
↓
Pod execution
↓
Logs retrieved
```