## Objective

The goal of this series is only to give you an idea, that containers are just the isolated process that do not need container runtime (docker). Vanialla Linux itself is capable of running the containerized process and we'll follow the guide along to create our own container without any runtime.

## What is a container

Container is a process that is running in it's own linux namespace, restricted resource access using control groups and secured by denying access to some elevated system calls using seccomp profiles.

## What is a linux namespace

Linux namespaces is an abstraction layer across system resources, wherein process running inside the namespace *ns1* cant see the resources for the process running inside namespace *ns2*.  

## What is Linux ControlGroup

Namespaces restrict what process can see, control groups restrict what they can access. It allows you to allocate, restrict and monitor the resources like cpu, memory, network etc.

## What is Seccomp Profile

Seccomp is a kernel feature which restricts the system calls that containers can make, hence ensuring they can not break into the system and do something catastrophic.

## Unshare System Call

Unshare creates a new namespace (using various arguments) and is scoped to the member process. 
https://man7.org/linux/man-pages/man1/unshare.1.html


## Mount Namespace: 

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



now you will notice that only the bash which pid=1 and the new ps -aef are the only process, we just isolated process namespace

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