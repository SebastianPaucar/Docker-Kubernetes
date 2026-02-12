# **Isolated nerdctl Containerd Setup**

## Overview

This is essentially a full “dual container runtime setup” on your node, with explicit separation of k3s/containerd, nerdctl/containerd, and Docker. The goal is to set up an **isolated instance of containerd** for `nerdctl` while keeping the system Docker and k3s containerd intact. This allows running nerdctl containers independently without interfering with the system container runtime.

---

## Installation & Setup

1. **Inspecting running containerd processes:**

The command:

```bash
[root@lab-x38 ~]# ps -eo pid,cmd | grep -E 'containerd' | grep -v grep || true
 181907 containerd
  182566 /var/lib/rancher/k3s/data/86a616cdaf0fb57fa13670ac5a16f1699f4b2be4772e842d97904c69698ffdc2/bin/containerd-shim-runc-v2 -namespace k8s.io -id 5a6a3c8636c3b4015b01ce127c1cbc5ce0d3e4751de1a29d79690a89cd41acee -address /run/k3s/containerd/containerd.sock
   182610 /var/lib/rancher/k3s/data/86a616cdaf0fb57fa13670ac5a16f1699f4b2be4772e842d97904c69698ffdc2/bin/containerd-shim-runc-v2 -namespace k8s.io -id e162d2bee52ff78a90c84c181de203f16e028b8dfa334d4f185dbbca7d4289d7 -address /run/k3s/containerd/containerd.sock
    182650 /var/lib/rancher/k3s/data/86a616cdaf0fb57fa13670ac5a16f1699f4b2be4772e842d97904c69698ffdc2/bin/containerd-shim-runc-v2 -namespace k8s.io -id 46e674ad6403f3322cbc27b1ad27a89b91bed25adbc76606c45a18d3513ace88 -address /run/k3s/containerd/containerd.sock
     183730 /var/lib/rancher/k3s/data/86a616cdaf0fb57fa13670ac5a16f1699f4b2be4772e842d97904c69698ffdc2/bin/containerd-shim-runc-v2 -namespace k8s.io -id c3278b152146cf07c6fb8510677f24dfda012b28e42625d3615aa091edd43007 -address /run/k3s/containerd/containerd.sock
      183767 /var/lib/rancher/k3s/data/86a616cdaf0fb57fa13670ac5a16f1699f4b2be4772e842d97904c69698ffdc2/bin/containerd-shim-runc-v2 -namespace k8s.io -id d9cff4e2fc55d1d55f12d54c5f89898d0dff411e340741fd3a8b10b422ff481e -address /run/k3s/containerd/containerd.sock
       312067 /usr/local/bin/containerd
```

lists all processes related to containerd. Here we can find:

* The k3s containerd shim processes (`containerd-shim-runc-v2`) bound to `/run/k3s/containerd/containerd.sock`.
* A standalone containerd process at `/usr/local/bin/containerd`.

Then the command:

```bash
[root@lab-x38 ~]# ss -lx | grep containerd || ls -l /run/containerd* /run/*containerd* 2>/dev/null || true
u_str LISTEN 0      4096                                            /run/k3s/containerd/containerd.sock.ttrpc 2981483            * 0
u_str LISTEN 0      4096                                                  /run/k3s/containerd/containerd.sock 2981484            * 0
u_str LISTEN 0      4096   /run/containerd/s/c66eab0b954e0e90379fefbda67abe10c873dfd11aaddfcebcd9c0090a571611 2991290            * 0
u_str LISTEN 0      4096   /run/containerd/s/b8aeb0dc11e1fb98c56d2ce63eb43a1c5a14c9ee590905020ad4e701d11150a1 2979687            * 0
u_str LISTEN 0      4096   /run/containerd/s/355c1523c1a8d6ca7ecaf2850848a3139010f6a20fb9a14ce2a96c6de9f7bac0 2982629            * 0
u_str LISTEN 0      4096                                                /run/containerd/containerd.sock.ttrpc 5554853            * 0
u_str LISTEN 0      4096                                                      /run/containerd/containerd.sock 5554854            * 0
u_str LISTEN 0      4096   /run/containerd/s/666ab3473b1619dc9e466f69f1e705c550ecaec7aec925d22f1215d4f53913d8 2996503            * 0
u_str LISTEN 0      4096   /run/containerd/s/0a588ee616cad3e3aef22a35e6940fc73aaf582250255a2007d5fe5b13bbb847 3001398            * 0
```

lists UNIX domain sockets listening for containerd. Sockets for both `/run/containerd/...` and `/run/k3s/containerd/...` are observed. Now we can kill:

```bash
kill 312067
```

That sends a signal to that specific containerd process and terminates that instance. This removed the process that owned `/run/containerd/containerd.sock` at that moment. Systemd launched a new containerd process (due to a previous `systemctl enable --now containerd`).

---

2. **Stop and mask system containerd**

```bash
kill 425596
systemctl stop containerd
systemctl disable containerd
systemctl mask containerd
```

* You killed a new standalone systemd containerd process.
* Disabled its systemd service and masked it to prevent accidental automatic startup.
* After this, `/run/containerd/containerd.sock` still existed, but the process was gone.

---

2. **Clean old system containerd sockets**

```bash
rm -f /run/containerd/containerd.sock /run/containerd/containerd.sock.ttrpc
```

* Removed stale containerd socket files.

---

3. **Setting up a separate containerd-nerdctl**

```bash
mkdir -p /etc/containerd-nerdctl /run/containerd-nerdctl \
         /var/lib/containerd-nerdctl/{overlayfs,blockfile,btrfs,devmapper,erofs,native,zfs}
	 chown -R root:root /var/lib/containerd-nerdctl /run/containerd-nerdctl
	 chmod 755 /var/lib/containerd-nerdctl /run/containerd-nerdctl
```

---

4. **Generate default nerdctl containerd config**

```bash
containerd config default > /etc/containerd-nerdctl/config.toml
```

Edit `/etc/containerd-nerdctl/config.toml` to use:

```bash
[root@lab-x38 ~]# grep nerdctl /etc/containerd-nerdctl/config.toml
root = '/var/lib/containerd-nerdctl'
state = '/run/containerd-nerdctl'
  address = '/run/containerd-nerdctl/containerd.sock'
      path = "/var/lib/containerd-nerdctl/containerd.db"
          root_path = '/var/lib/containerd-nerdctl/blockfile'
	      root_path = '/var/lib/containerd-nerdctl/btrfs'
	          root_path = '/var/lib/containerd-nerdctl/devmapper'
		      root_path = '/var/lib/containerd-nerdctl/erofs'
		          root_path = '/var/lib/containerd-nerdctl/native'
			      root_path = '/var/lib/containerd-nerdctl/overlayfs'
			          root_path = '/var/lib/containerd-nerdctl/zfs'
```

And also:

```bash
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
            BinaryName = ''
	                CriuImagePath = ''
			            CriuWorkPath = ''
				                IoGid = 0
						            IoUid = 0
							                NoNewKeyring = false
									            Root = ''
										                ShimCgroup = ''
												            SystemdCgroup = true
													    …
													    #[cgroup]
													    #  path = '/nerdctl'
```

This completely separates nerdctl’s containerd instance from the system containerd used by k3s or Docker by setting `/run/containerd-nerdctl/containerd.sock` and `/var/lib/containerd-nerdctl/` to create a dedicated, isolated containerd root for nerdctl, with:

* its own socket
* its own metadata DB
* its own snapshots
* its own images
* its own runtime state

To finally have:

```bash
k3s containerd → /run/k3s/containerd/containerd.sock
system containerd → /run/containerd/containerd.sock
nerdctl containerd → /run/containerd-nerdctl/containerd.sock
```

with no collisions, no accidental use of the wrong containerd, and 100% predictable nerdctl CLI behavior. `SystemdCgroup = true` instructs nerdctl’s runc to use systemd as the cgroup manager instead of the “cgroupfs” backend.

---

5. **Install nerdctl systemd service**

Touch `/etc/systemd/system/containerd-nerdctl.service` and edit it like this:

```bash
[root@lab-x38 ~]# cat  /etc/systemd/system/containerd-nerdctl.service
[Unit]
Description=containerd container runtime for nerdctl (isolated)
After=network.target
Wants=network.target

[Service]
ExecStart=/usr/local/bin/containerd --config /etc/containerd-nerdctl/config.toml
ExecReload=/bin/kill -s HUP $MAINPID
KillMode=process
Restart=always
RestartSec=5
Delegate=yes
LimitNOFILE=1048576
LimitNPROC=infinity
TasksMax=infinity
OOMScoreAdjust=-999
Type=notify

[Install]
WantedBy=multi-user.target
```

This creates a dedicated systemd service whose only job is to run an isolated instance of containerd exclusively for nerdctl. Normally `/usr/bin/containerd` is the system containerd used by Docker or k3s; nerdctl can use the system containerd, but for an isolated instance you need a separate systemd service.

```bash
systemctl daemon-reload
systemctl enable --now containerd-nerdctl
systemctl status containerd-nerdctl
```

You can see:

```bash
[root@lab-x38 ~]# systemctl status containerd-nerdctl
● containerd-nerdctl.service - containerd container runtime for nerdctl (isolated)
     Loaded: loaded (/etc/systemd/system/containerd-nerdctl.service; enabled; preset: disabled)
          Active: active (running) since Fri 2025-11-14 17:57:50 MST; 1min 46s ago
	     Main PID: 433761 (containerd)
	           Tasks: 21
		        Memory: 20.0M
			        CPU: 146ms
				     CGroup: /system.slice/containerd-nerdctl.service
				                  └─433761 /usr/local/bin/containerd --config /etc/containerd-nerdctl/config.toml
```

---

6. **Verify nerdctl containerd sockets**

```bash
[root@lab-x38 ~]# ss -lx | grep containerd-nerdctl
u_str LISTEN 0      4096                                        /run/containerd-nerdctl/containerd.sock.ttrpc 7904716            * 0
u_str LISTEN 0      4096                                              /run/containerd-nerdctl/containerd.sock 7904717            * 0
```

---

## Testing nerdctl

1. **Check nerdctl info**

```bash
[root@lab-x38 ~]# nerdctl --address=/run/containerd-nerdctl/containerd.sock info
Client:
 Namespace:	default
  Debug Mode:	false

Server:
 Server Version: v2.2.0
  Storage Driver: overlayfs
   Logging Driver: json-file
    Cgroup Driver: systemd
     Cgroup Version: 2
      Plugins:
        Log:     fluentd journald json-file none syslog
	  Storage: native overlayfs
	   Security Options:
	     seccomp
	        Profile: builtin
		  cgroupns
		   Kernel Version:   5.14.0-503.11.1.el9_5.x86_64
		    Operating System: AlmaLinux 9.5 (Teal Serval)
		     OSType:           linux
		      Architecture:     x86_64
		       CPUs:             16
		        Total Memory:     62.42GiB
```

2. **Run a test nginx container**

```bash
[root@lab-x38 ~]# nerdctl --address=/run/containerd-nerdctl/containerd.sock run -d --name test-nginx -p 8080:80 nginx:alpine
docker.io/library/nginx:alpine:                                                   resolved       |++++++++++++++++++++++++++++++++++++++| 
index-sha256:b3c656d55d7ad751196f21b7fd2e8d4da9cb430e32f646adcf92441b72f82b14:    done           |++++++++++++++++++++++++++++++++++++++| 
manifest-sha256:667473807103639a0aca5b49534a216d2b64f0fb868aaa801f023da0cdd781c7: done           |++++++++++++++++++++++++++++++++++++++| 
config-sha256:d4918ca78576a537caa7b0c043051c8efc1796de33fee8724ee0fff4a1cabed9:   done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:2d35ebdb57d9971fea0cac1582aa78935adf8058b2cc32db163c98822e5dfa1b:    done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:8f6a6833e95d43ac524f1f9c5e7c1316c1f3b8e7ae5ba3db4e54b0c5b910e80a:    done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:bdabb0d442710d667f4fd871b5fd215cc2a430a95b192bc508bf945b8e60999b:    done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:3eaba6cd10a374d9ed629c26d76a5258e20ddfa09fcef511c98aa620dcf3fae4:    done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:194fa24e147df0010e146240d3b4bd25d04180c523dc717e4645b269991483e3:    done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:d9a55dab5954588333096b28b351999099bea5eb3c68c10e99f175b12c97198d:    done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:ff8a36d5502a57c3fc8eeff48e578ab433a03b1dd528992ba0d966ddf853309a:    done           |++++++++++++++++++++++++++++++++++++++| 
layer-sha256:df413d6ebdc834bccf63178455d406c4d25e2c2d38d2c1ab79ee5494b18e5624:    done           |++++++++++++++++++++++++++++++++++++++| 
elapsed: 5.4 s                                                                    total:  5.4 Mi (1022.0 KiB/s)                                    
86d8e314bdf43408f71336cf0b16ed593de484716664151f3e9b1ba2652597e2
```

```bash
[root@lab-x38 ~]# nerdctl --address=/run/containerd-nerdctl/containerd.sock ps
CONTAINER ID    IMAGE                             COMMAND                   CREATED           STATUS    PORTS                   NAMES
86d8e314bdf4    docker.io/library/nginx:alpine    "/docker-entrypoint.…"    17 seconds ago    Up        0.0.0.0:8080->80/tcp    test-nginx
```

