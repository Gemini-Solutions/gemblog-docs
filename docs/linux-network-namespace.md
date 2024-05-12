
ip netns add netns1  ip netns delete netns1

ip netns exec netns1 ip link set dev lo up

ip link add veth0 type veth peer name veth1

ip link set veth1 netns netns1

ip addr add 192.168.0.1/24 dev veth0

ip link set dev veth0 up

ip netns exec netns1 ip addr add 192.168.0.2/24 dev veth1
ip netns exec netns1 ip link set dev veth1 up

**Cleanup**
ip netns delete netns1
ip link del veth0

https://www.gilesthomas.com/2021/03/fun-with-network-namespaces