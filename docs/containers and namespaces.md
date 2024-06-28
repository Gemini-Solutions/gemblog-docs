## Objective

The objective of this series is to demonstrate that containers, which are essentially isolated processes, can be implemented without relying on a container runtime like Docker. Vanilla Linux itself can facilitate the execution of containerized processes. Throughout this guide, we will explore how to create and manage our own containers independently.

## What is a Container

A container is a process running within its own Linux namespace, leveraging restricted resource access through control groups (cgroups), and secured by limiting access to certain system calls using Seccomp profiles.

## What is a Linux Namespace

Linux namespaces provide an abstraction layer for system resources. Processes running inside one namespace (e.g., `ns1`) are isolated from processes running in another namespace (`ns2`). This isolation ensures that each namespace has its own view of system resources.

## What are Linux Control Groups (cgroups)

Control groups are used to manage and monitor system resources such as CPU, memory, and network bandwidth. They enable allocation and restriction of these resources among processes or groups of processes, ensuring efficient resource utilization and isolation.

## What is a Seccomp Profile

Seccomp (Secure Computing Mode) is a Linux kernel feature that restricts the system calls available to a process. By using Seccomp profiles, container environments can limit the set of system calls that containerized applications can make. This restriction helps prevent potential security breaches and ensures that containers cannot perform unauthorized actions on the host system.


## Unshare System Call

The `unshare` system call in Linux is pivotal for creating new namespaces, which are essential for containerization without relying on Docker or any container runtime. This system call allows a process to create and manage its own namespaces, thereby isolating its execution environment from the rest of the system.
The `unshare` command, detailed in its [man page](https://man7.org/linux/man-pages/man1/unshare.1.html), enables a process to disassociate from certain namespaces or create new ones. By specifying different namespace types as arguments (such as network, mount, IPC, PID, user, or UTS namespaces), `unshare` empowers developers to control the level of isolation and resource visibility of their processes. Now let's start to create our own isolated process.

## Mount Namespace

Mount (MNT) namespaces are a powerful tool for creating per-process file system trees (root filesystem views). If you simply create the mount namespace using ```unshare```, nothing would really happen, The reason for this is that systemd defaults to recursively sharing the mount points with all new namespaces
let's simply create a new namespace using unshare and only the mount namespace.

```unshare -m```
```df -h```

we are seeing the exact same mount points which we dont want, so let's create our own filesystem using alpine linux and use it as the mountpoint for our unshared process (bash). Let's use the most famous minimalist root filesystem, alpine for our purpose.

```mkdir alpine-rootfs && cd alpine-rootfs```
```curl -o alpine.tar.gz https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.0-x86_64.tar.gz```
```tar xfz alpine.tar.gz && rm -rf alpine.tar.gz```

while unshare let us create a new namespace and runs the command in the new namespace in this case ```unshare -m``` with new mount namespace, we have another function, chroot, which changes the root directory (in our case alpine we downloaded)

```chroot absolute-path-alpine-rootfs /bin/sh```

the /bin/sh is the command that is inside the root file system being used for chroot, i.e alpine, and we also need to update the PATH variable ```PATH="$PATH:/bin:/sbin"```

now let's run some commands to see what happened, 
```ps -aef```

well no process, did we really achieve isolation? duhh!! not really, it's just coz the /proc is empty. What about the network namespace, let's try to see what all netowrk devices and IP addresses we have, ```ip addr```. Again, we are seeing the information from the host, let's also try to see the details of the current user and the hostname as well. ```id``` & ```hostname```. 
let's see all the host process inside the chroot as well,
```mount -t proc proc /proc``` and then run ```ps -aef```. Well everything is visible.

```unshare -p -f --mount-proc=<absolute-path-alpine-rootfs>/proc/ chroot <absolute-path-alpine-rootfs> /bin/sh```

Note: --mount-proc= will only work if the proc is mounted to procfs of the alpineroot fs, if it's unmounted somehow then using --mount-proc with unshare have no effect, instead, simply run unshare and then mount the proc again, like this

```unshare -p -f chroot <absolute-path-alpine-rootfs> /bin/sh```
```mount -t proc proc /proc```
```ps -aef```


## Network Namespace

Now you will notice that only the bash which pid=1 and the new ps -aef are the only process, we just isolated process and mount namespace. But it's of no use as such, let's extend our example to run a basic server in isolation. For that we'll need our own network namespaces with virtual routes. Let's get it going. 

* Create network namespace netns1 ```ip netns add netns1```
* Execing into network namespace and enabling loopback ```ip netns exec netns1 ip link set dev lo up```
* Creating a virtual ethernet pair ```ip link add veth0 type veth peer name veth1```
* Moving one end of pair to the namespace ```ip link set veth1 netns netns1```
* Assigns an IP address and subnet mask to the veth0 network interface```ip addr add 192.168.0.1/24 dev veth0```
* Brings the veth0 network interface up ```ip link set dev veth0 up```
* Assigns an IP address and subnet mask to the veth1 network interface inside the netns1 network namespace ```ip netns exec netns1 ip addr add 192.168.0.2/24 dev veth1```
* Brings the veth1 network interface up inside the netns1 network namespace ```ip netns exec netns1 ip link set dev veth1 up```

#### Running inside the network namespace

After all the commands, we'll tweak our unshare to actually run inside the network namespace and see our ip routes
```ip netns exec netns1 unshare -pf  chroot /root/alp12/ ip addr```. And we'll see the loopback and the veth1 attached to our namespace.
Let's run a golang server inside our isolated environment and access it from the host with virtual ip.





docker create --name container-name image-name
docker cp container-name:/path/src ./target 

install control groups yum
yum install -y libcgroup-tools
cgcreate -g memory,cpu:/mygroup
250 MB
echo 262144000 > /sys/fs/cgroup/memory/mygroup/memory.limit_in_bytes

limiting CPU cfs_quota_us: total amount of time in micro seconds processes can run in a cgroup, 
in this it says the process can run for 0.5 seconds. (it works in tandem with cpu.cfs_period_us)
echo 50000 > /sys/fs/cgroup/cpu/mygroup/cpu.cfs_quota_us

It specifies the time in microseconds for how regularly can the process request the resources which are restriced by cfs_quota_us
echo 1000000  > /sys/fs/cgroup/cpu/mygroup/cpu.cfs_period_us

***
It's easy to get the memory allocated hence it kills if it can not allocate, where as the cpu restriction can be witnessed by checking the time it takes to do the same task by reducing the cfs_quota_us

time cgexec -g memory,cpu:/mygroup ./mem



**Cleanup**
ip netns delete netns1
ip link del veth0

https://www.gilesthomas.com/2021/03/fun-with-network-namespaces









mountnamespace : https://book.hacktricks.xyz/linux-hardening/privilege-escalation/docker-security/namespaces/mount-namespace
mount chroot : https://unix.stackexchange.com/questions/464033/understanding-how-mount-namespaces-work-in-linux
chroot : https://unix.stackexchange.com/questions/456620/how-to-perform-chroot-with-linux-namespaces



https://blog.quarkslab.com/digging-into-linux-namespaces-part-2.html
https://www.redhat.com/sysadmin/mount-namespaces
https://linuxera.org/containers-under-the-hood/
https://github.com/util-linux/util-linux/issues/648



## Some Interesting References
https://medium.com/@razika28/inside-proc-a-journey-through-linuxs-process-file-system-5362f2414740
https://man7.org/linux/man-pages/man5/proc.5.html
https://www.gilesthomas.com/2021/03/fun-with-network-namespaces
https://danishpraka.sh/posts/build-docker-image-from-scratch/
https://blog.quarkslab.com/digging-into-linux-namespaces-part-1.html
https://www.toptal.com/linux/separation-anxiety-isolating-your-system-with-linux-namespaces
https://www.redhat.com/sysadmin/mount-namespaces