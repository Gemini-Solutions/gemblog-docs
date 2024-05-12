## What Are Service Mesh

Before we try to understand what service mesh are, let's try to answer some questions below

* Keep track of IP addresses of all the ephemeral workloads and number of instances
* Achieve loadbalancing (client/server side), rate limiting, circuit breaker pattern etc.
* Enable authN/authZ for inter service communication
* Enable mTLS
* Observabilty into network traffic.

Imagine app developers have to write logic for all the features above which obviously would be replicated by other developers with no governance in place. Service mesh help achieve all this with predefined principals and configuration. Once such service mesh is Istio (enabled with envoy as side car proxy).

![Istio Service Mesh](./assets/service%20mesh/istio-architecture.png)

*We'd be going through the setup on Istio is deployed in K8s and abstract authN/authZ*

## Installation and Istio Components

Istio's own documentation outlines each step to [install istio in kubernetes](https://istio.io/latest/docs/setup/getting-started/) as well and more details on the [components here](https://istio.io/v1.4/docs/ops/deployment/architecture/#components). We are interested in envoy's internal working and extending it's capabilities.

To enable side car injection in kubernetes ```kubectl label namespace default istio-injection=enabled```

## What is Side Car and How it works

Side in context of kubernetes is a small memory foot print container that is part of the same pod and shaes network and process namespaces. These [namespaces are linux namespaces](https://man7.org/linux/man-pages/man7/namespaces.7.html) and not kubernetes'. When Istio's installted it creates a mutating webhook configuration in your cluster and has config like

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

Init container is job container that starts before the actual pod starts up and in this case it updates the Iptables (the default traffic interception method in Istio, and can also use BPF, IPVS, etc.)

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


reference : https://istio.io/v1.14/blog/2019/data-plane-setup/
reference : https://jimmysong.io/en/blog/understanding-how-envoy-sidecar-intercept-and-route-traffic-in-istio-service-mesh/
reference : https://jimmysongio.medium.com/sidecar-injection-transparent-traffic-hijacking-and-routing-process-in-istio-explained-in-detail-d53e244e0348