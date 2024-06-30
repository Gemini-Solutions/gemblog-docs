## Objective

This series is to demonstrate that containers, which essentially are isolated processes, can be implemented without relying on a container runtime like Docker. Vanilla Linux itself can facilitate the execution of containerized processes. Throughout this guide, we will explore how to create and manage our own containers independently.

## What is a Container

A container is a process running within its own Linux namespace, leveraging restricted resource access through control groups (cgroups), and secured by limiting access to certain system calls using Seccomp profiles.

## What is a Linux Namespace

Linux namespaces provide an abstraction layer for system resources. Processes running inside one namespace (e.g., `ns1`) are isolated from processes running in another namespace (`ns2`). This isolation ensures that each namespace has its own view of system resources. We'll leverage ```unshare``` to isolate the namespaces.

## What are Linux Control Groups (cgroups)

Control groups are used to manage and monitor system resources such as CPU, memory, and network bandwidth. They enable allocation and restriction of these resources among processes or groups of processes, ensuring efficient resource utilization and isolation. We'll create a control group, assign memory and CPU limits and run the process with the control group. 

## What is a Seccomp Profile

Seccomp (Secure Computing Mode) is a Linux kernel feature that restricts the system calls available to a process. By using Seccomp profiles, container environments can limit the set of system calls that containerized applications can make. This restriction helps prevent potential security breaches and ensures that containers cannot perform unauthorized actions on the host system.


## Unshare System Call

The {==_unshare_==} system call in Linux is pivotal for creating new namespaces, which are essential for containerization without relying on Docker or any container runtime. This system call allows a process to create and manage its own namespaces, thereby isolating its execution environment from the rest of the system.
The `unshare` command, detailed in its [man page](https://man7.org/linux/man-pages/man1/unshare.1.html), enables a process to disassociate from certain namespaces or create new ones. By specifying different namespace types as arguments (such as network, mount, IPC, PID, user, or UTS namespaces), `unshare` empowers developers to control the level of isolation and resource visibility of their processes. Now let's start to create our own isolated process.

## Mount Namespace

Mount (MNT) namespaces are a powerful tool for creating per-process file system trees (root filesystem views). If you simply create the mount namespace using ```unshare```, nothing would really happen, The reason for this is that systemd defaults to recursively sharing the mount points with all new namespaces.
Simply create a new namespace using unshare and only the mount namespace.

```
unshare -m
df -h
```

we are seeing the exact same mount points which we dont want, so we need to create our own filesystem using alpine linux and use it as the mountpoint for our unshared process (bash). Let's use the most famous minimalist root filesystem, alpine for our purpose.

``` sh
mkdir alpine-rootfs && cd alpine-rootfs
curl -o alpine.tar.gz https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.0-x86_64.tar.gz
tar xfz alpine.tar.gz && rm -rf alpine.tar.gz
```

while unshare helps create a new namespace and runs the command in the new namespace in this case ```unshare -m``` with new mount namespace, we have another function ```chroot``` which changes the root directory (in our case alpine we downloaded)

```chroot absolute-path-alpine-rootfs /bin/sh```

the /bin/sh is the command that is inside the root file system being used for chroot, i.e alpine, and we also need to update the PATH variable ```PATH="$PATH:/bin:/sbin"```

now let's run some commands to see what happened, 
```ps -aef```

well no process, did we really achieve isolation? duhh!! not really, it's just coz the /proc is empty. What about the network namespace, Try to see what all netowrk devices and IP addresses we have, ```ip addr```. Again, we are seeing the information from the host, let's also try to see the details of the current user and the hostname as well. ```id``` & ```hostname```. 
And what about the host process inside the chroot,
```mount -t proc proc /proc``` and then run ```ps -aef```. Well everything is visible. To achieve isolation from the process and use our own filesystem, we need to use chroot intandem with unshare
```unshare -p -f --mount-proc=<absolute-path-alpine-rootfs>/proc/ chroot <absolute-path-alpine-rootfs> /bin/sh```

Note: --mount-proc= will only work if the proc is mounted to procfs of the alpineroot fs, if it's unmounted somehow then using --mount-proc with unshare have no effect, instead, simply run unshare and then mount the proc again, like this

```unshare -p -f -m chroot <absolute-path-alpine-rootfs> /bin/sh
mount -t proc proc /proc
ps -aef```.


## Network Namespace

Now you will notice that only the bash which pid=1 and the new ps -aef are the only process, we just isolated process and mount namespace. But it's of no great use as such, let's extend our example to run a basic server in isolation. For that we'll need our own network namespaces with virtual routes. 

* Create network namespace netns1 ```ip netns add netns1```
* Execing into network namespace and enabling loopback ```ip netns exec netns1 ip link set dev lo up```
* Creating a virtual ethernet pair ```ip link add veth0 type veth peer name veth1```
* Moving one end of pair to the namespace ```ip link set veth1 netns netns1```
* Assigns an IP address and subnet mask to the veth0 network interface```ip addr add 192.168.0.1/24 dev veth0```
* Brings the veth0 network interface up ```ip link set dev veth0 up```
* Assigns an IP address and subnet mask to the veth1 network interface inside the netns1 network namespace ```ip netns exec netns1 ip addr add 192.168.0.2/24 dev veth1```
* Brings the veth1 network interface up inside the netns1 network namespace ```ip netns exec netns1 ip link set dev veth1 up```

#### Running inside the network namespace

We'll try to run a golang server in the isolated namespace just created and try access it locally from the host to the virtual ip address of network namespace. For this we need to take help of docker to build our binary and extract it and put in our alpine filesystem. (If you already have GO binaries you can skip this and simply compile the file.)

* ```docker build -t hello-world -f``` [Dockerfile](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/containers/Dockerfile)
* ```docker create --name extract-hello -t hello-world```
* ```docker cp extract-hello:/app/hello-world .```
* ```cp hello-world <absolute-path-alpine-rootfs>/home/```

After all the commands, we'll tweak our unshare to actually run inside the network namespace and see our ip routes
```ip netns exec netns1 unshare -pf  chroot /root/alp12/ ip addr```. We'll see the loopback and the veth1 attached to our namespace.
And one final step ```ip netns exec netns1 unshare -fmiup  chroot /root/alp12/ /home/hello-world &```. We can access the server from the host using ```curl 192.168.0.2:8080```



## Cgroups In Action

So far we have seen how to isolate the processes running in linux, so that, they can not see process information outside their namespace, but what about restricting their access to resources. This is where control groups come into play. We'll be restricting access to memory and cpu resources for our basic golang. Follow the steps below to create a controlgroup and run a very basic stress test only to see it getting killed. (I had cgroup v1, hence using an old approach, you can follow similar approach with bunch of googling to see if you have control group v2 enabled and how to do the same)

* Creating a controlgroup with name my group : ```cgcreate -g memory,cpu:/mygroup```
* Restricting access to only 250MB : ```echo 262144000 > /sys/fs/cgroup/memory/mygroup/memory.limit_in_bytes```
* Build the [golang file](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/containers/memory_cpu_stress.go) this creates 500MB block and extract the binary as done in earlier steps
* Running it with our cgroup: ```time cgexec -g memory,cpu:/mygroup ./memory_cpu_stress```.  You'll notice the process got killed.
* Increasing the memory to what's needed(500+ MB) and rerunning it succeeds. ```echo 576716800 > /sys/fs/cgroup/memory/mygroup/memory.limit_in_bytes```. Run the process again to see it succeeding but do note the time.

We'll now restrict the CPU rescoures. CPU resources are not straight forward as it's dependent on the time for which the process can request the CPU till it's throttled.

* Limiting CPU cfs_quota_us: Total amount of time in micro seconds processes can run in a cgroup. ```echo 1000 > /sys/fs/cgroup/cpu/mygroup/cpu.cfs_quota_us```. The process in this group can only run for 1ms. (it works in tandem with cpu.cfs_period_us)
* Limiting CPU cpu.cfs_period_us: It specifies the time in microseconds for how regularly can the process request the resources which are restriced by cfs_quota_us. ```echo 1000000  > /sys/fs/cgroup/cpu/mygroup/cpu.cfs_period_us```, this limits the process to request the cpu resources every 1second only (10^6 micro second).
* Run the process again and see the time it takes to complete (if it ever does.). Adjust ```cfs_quota_us``` to increase the quota and have some tries to see the process completing and running slow as we restricted it's access to CPU resources


## Appreciating Docker & Runtimes

After all the hassle and setup our final command to run a restricted process would be, 

``` 
cgexec -g memory,cpu:/mygroup \
ip netns exec netns1 \
unshare -fmiup  chroot /root/alpine-root-fs/ /home/hello-world
```

Imagine doing this for each process and still be unsure of security issues and vulnerabilities that can pop up, we still are missing on seccomp profiles which [docker does for us](https://docs.docker.com/engine/security/seccomp/#pass-a-profile-for-a-container). These profiles can be complex and I am not a security expert hence had no idea how could I breach my namespace even if running as a root.


## References

Picking and summing it up from the amazing blogs and references : 

* mountnamespace : <https://book.hacktricks.xyz/linux-hardening/privilege-escalation/docker-security/namespaces/mount-namespace>
* mount chroot : <https://unix.stackexchange.com/questions/464033/understanding-how-mount-namespaces-work-in-linux>
* chroot : <https://unix.stackexchange.com/questions/456620/how-to-perform-chroot-with-linux-namespaces>
* <https://www.gilesthomas.com/2021/03/fun-with-network-namespaces>
* <https://blog.quarkslab.com/digging-into-linux-namespaces-part-2.html>
* <https://www.redhat.com/sysadmin/mount-namespaces>
* <https://linuxera.org/containers-under-the-hood/>
* <https://github.com/util-linux/util-linux/issues/648>
* <https://medium.com/@razika28/inside-proc-a-journey-through-linuxs-process-file-system-5362f2414740>
* <https://man7.org/linux/man-pages/man5/proc.5.html>
* <https://www.gilesthomas.com/2021/03/fun-with-network-namespaces>
* <https://danishpraka.sh/posts/build-docker-image-from-scratch/>
* <https://blog.quarkslab.com/digging-into-linux-namespaces-part-1.html>
* <https://www.toptal.com/linux/separation-anxiety-isolating-your-system-with-linux-namespaces>
* <https://www.redhat.com/sysadmin/mount-namespaces>
* <https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/6/html/resource_management_guide/sec-cpu#sec-cpu>