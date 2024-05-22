## Introduction

The blog here is the first of the two series blog that explains how to enable external authorization using service mesh Istio and Envoy. This explores how does service mesh work and intercept inbound/outbound calls and the [second one](./service-mesh-authN-authZ.md) shows how envoy can be extended for authentication leveraging opa for authorization. We are trying to abstract away all the authN/authZ logic out of the application.

## What is a Service Mesh

Before we try to understand what service mesh are, let's try to answer some questions below

How to? ....

* Keep track of IP addresses of all the ephemeral workloads and number of instances
* Achieve loadbalancing (client/server side), rate limiting, circuit breaker pattern etc.
* Enable authN/authZ for inter service communication
* Enable mTLS
* Observabilty into network traffic.

Imagine app developers have to write logic for all the features above which obviously would be replicated by other developers with no governance in place. Service mesh help achieve all this with predefined principals and configuration. Once such service mesh is Istio (enabled with envoy as side car proxy).

![Istio Service Mesh](./assets/service%20mesh/istio-architecture.png)

*We'd be going through the setup on Istio, deployed in K8s and abstract authN/authZ*

## Installation and Istio Components

Istio's own documentation outlines each step to [install istio in kubernetes](https://istio.io/latest/docs/setup/getting-started/) as well and more details on the [components here](https://istio.io/v1.4/docs/ops/deployment/architecture/#components). We are interested in envoy's internal working and extending it's capabilities.

Once installed, to enable side car injection in kubernetes ```kubectl label namespace default istio-injection=enabled```

## What is Side Car and How it works

Side car in context of kubernetes is a small memory foot print container that is part of the same pod and shares network and process namespaces. These [namespaces are linux namespaces](https://man7.org/linux/man-pages/man7/namespaces.7.html) and not kubernetes'. When Istio's installted it creates a mutating webhook configuration in your cluster and has config like

```kubectl get mutatingwebhookconfiguration istio-sidecar-injector -oyaml```

```
    service:
      name: istiod
      namespace: istio-system
      path: /inject
      port: 443
  failurePolicy: Fail
  matchPolicy: Equivalent
  name: namespace.sidecar-injector.istio.io
  namespaceSelector:
    matchLabels:
      istio.io/deactivated: never-match
  objectSelector:
    matchLabels:
      istio.io/deactivated: never-match
  reinvocationPolicy: Never
  rules:
  - apiGroups:
    - ""
    apiVersions:
    - v1
    operations:
    - CREATE
    resources:
    - pods
    scope: '*'

```

It watches for any pod that's being created and calls the mutating webhook deployed as **istiod** which inturn adds an [initContainer](https://github.com/istio/istio/blob/master/pkg/kube/inject/webhook.go#L1031) as well as the side car container. The initContainer updates the Iptables on the host which ensures that all the inbound/outbound traffic is intercepted by side car container and the side car container is the actual envoy proxy. 

## What is init Container

Init container is job container that starts before the actual pod starts up and in this case it updates the Iptables (the default traffic interception method in Istio, and can also use BPF, IPVS, etc.). We'll analyze any pod that is in the cluster where the istio injection is enabled.

Let's see the configuration of init container. ```kubectl get pods <pod-name> -oyaml```

```
  initContainers:
  - args:
    - istio-iptables
    - -p
    - "15001"
    - -z
    - "15006"
    - -u
    - "1337"
    - -m
    - REDIRECT
    - -i
    - '*'
    - -x
    - ""
    - -b
    - '*'
    - -d
    - 15090,15021,15020
    - --log_output_level=default:info
    image: docker.io/istio/proxyv2:1.15.2
    imagePullPolicy: IfNotPresent
    name: istio-init

```

the istio-iptables is the utility written by istio folks to update the routing rules. We want to inspect the ip tables and the network rules for the container, but where and how should we do it.

```
A little Back Ground

There's plethora of content if you search for, life of a packet in kubernetes. And to summarize them all (which does not do justice to the authors and kuberentes itself, but serves our purpose), the packet enters the network interface of the host machine and checks the destination, if it matches any of the CIDR that it can serve, it pushes the packet up the network stack else relays back to the wire.
Once the packet is inside host, it checks for the iptable/ipvs rules on how the packet is to be routed and if it belongs to virtual interfaces the routing happens accordingly. In the end it's all about routing within the host.

Hence in our use case, we'd have to check for ip tables of that container's namespace (namespace of linux) and see how the routing looks for that process/container
```

## Init Container in action..

* Find the container ID and get the linux process ID of the container running. It does not matter any container of the pod should do as they share the same network namespace.
* The command would give you the containerID ```kubectl get pods -nats some-awesome-app -o jsonpath='{.status.containerStatuses[0].containerID}'```
* Grab the ID and get the process id on the host ```docker inspect <container-sha> --format '{{ .State.Pid }}'```
* Enter into the container linux namespace and grab it's iptables ```nsenter -t <process-id> -n iptables -t nat -S```

Exploring the output. We'd explore only rules that matter. Your output might be slightly different but overall it remains the same

#### Main Chain rules

```
-A PREROUTING -p tcp -j ISTIO_INBOUND
-A OUTPUT -p tcp -j ISTIO_OUTPUT
```
* All incoming TCP packets (in the PREROUTING chain) are sent to the ISTIO_INBOUND chain.
* All outgoing TCP packets (in the OUTPUT chain) are sent to the ISTIO_OUTPUT chain.

#### ISTIO_INBOUND Chain

```
-A ISTIO_INBOUND -p tcp -m tcp --dport 15008 -j RETURN
-A ISTIO_INBOUND -p tcp -m tcp --dport 15090 -j RETURN
-A ISTIO_INBOUND -p tcp -m tcp --dport 15021 -j RETURN
-A ISTIO_INBOUND -p tcp -m tcp --dport 15020 -j RETURN
-A ISTIO_INBOUND -p tcp -j ISTIO_IN_REDIRECT
```

* These rules in the ISTIO_INBOUND chain return packets (skip further processing in this chain) if they are destined for ports 15008, 15090, 15021, or 15020. These ports are typically used by Istio for its own purposes.
* Any other TCP packets are redirected to the ISTIO_IN_REDIRECT chain.

#### ISTIO_IN_REDIRECT Chain

```
-A ISTIO_IN_REDIRECT -p tcp -j REDIRECT --to-ports 15006
```
* This rule redirects all TCP packets to port 15006. This port is used by Istio's sidecar proxy (Envoy) to intercept inbound traffic.


#### ISTIO_OUTPUT Chain

```
-A ISTIO_OUTPUT -s 127.0.0.6/32 -o lo -j RETURN
.
.
-A ISTIO_OUTPUT -j ISTIO_REDIRECT
```
* The packets from/to localhost are redirected internally and all the other packets are sent to the ISTIO_REDIRECT chain.

#### ISTIO_REDIRECT Chain

```
-A ISTIO_REDIRECT -p tcp -j REDIRECT --to-ports 15001
```
* This rule redirects all TCP packets to port 15001. This port is typically used by Istio's sidecar proxy to intercept outbound traffic.


Now that we established how does envoy intercepts the traffic and work at network layer. We can move forward to work at layer 7 of the OSI model i.e application layer nad use envoyproxy as per our needs.