## Introduction

The blog here explains how to enable external authorization using service mesh Istio and Envoy. The first part explores how does service mesh work and intercept inbound/outbound calls and the second one shows how the envoy can be extended for authentication leveraging opa for authorization. We are trying to abstract away all the authN/authZ logic out of the application.

## What Are Service Mesh

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

## What is Istio-proxy

Once the init container is done modifying the IP table routes, the envoy proxy is attached and does all the magic. Envoy/Istio proxy small-footprint edge and service proxy which is written in C++ , developed by folks at Lyft

## Extending Envoy's Capabilities using Istio Envoy Filter.

[Envoyfilter](https://istio.io/latest/docs/reference/config/networking/envoy-filter/) is the CRD written by Istio to extend the capabilites of side car proxy using yaml configuration which inturn uses envoy's [http filter](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/http_filters). Here's our use case.

* Incoming request must be checked against a valid JWT.
* Outbound request for interservice communication must automatically append the JWT
* The requests must also be processed by OPA for authZ

This is our [envoy filter](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/service-mesh/envoyfilter.yaml). We'd be going over what each and every section means.

#### Enabling JWT Filter

First we enable the [JWT filter](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/service-mesh/envoyfilter.yaml#L73) for every inbound request. Let's breakdown the configuration

```
  providers:
    ms_jwt_auth:
      forward: true
      forward_payload_header: claim
      from_headers:
      - name: Authorization
        value_prefix: 'Bearer '
      payload_in_metadata: jwt_payload
      remote_jwks:
        http_uri:
          cluster: ms_jwks_cluster
          timeout: 1s
          uri: https://login.microsoftonline.com/<tenant-id>/discovery/v2.0/keys
```

* JWT Filter takes in list of providers. These providers are the configuration of the auth server
* ```from_headers``` indicate that token has to be extracted from Authorization header
* ```payload_in_metadata``` stores the JWT's payload for future processing.

the [rules section](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/service-mesh/envoyfilter.yaml#L100) dicate if the JWT filter should be applied to a path or not, here's a sample match 

```
  - match:
      safe_regex:
        google_re2: {}
        regex: .*path3.*
  - match:
      prefix: /some/more/path/1
    requires:
      provider_name: tm_jwt_auth
```

* First match rule bypasses and does not apply filter if anything that matches path3
* Second match rule, applies JWT filter with provider ```tm_jwt_auth``` if request is of path ```/some/more/path/1```

The JWT filter autmatically verifies and validates the token using well known openid configuration endpoint for the providers by checking expiry and validating keys using JWKS.


#### Exploring Provider Configuration

The providers are configured with a [cluster type](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/service-mesh/envoyfilter.yaml#L85) for an out bound request which is configured using [envoy's transport tls socket filter](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/service-mesh/envoyfilter.yaml#L54).

```
 value:
   connect_timeout: 10s
   dns_lookup_family: V4_ONLY
   lb_policy: ROUND_ROBIN
   load_assignment:
     cluster_name: ms_jwks_cluster
     endpoints:
     - lb_endpoints:
       - endpoint:
           address:
             socket_address:
               address: login.microsoftonline.com
               port_value: 443
   name: ms_jwks_cluster
   transport_socket:
     name: envoy.transport_sockets.tls
     typed_config:
       '@type': type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
       sni: login.microsoftonline.com
```

* This is the cluster configuration as given in the providers section, in our case it's microsoft
* It fires off outbound query to microsoft to verify token in roundrobin fashion and timeout of 10seconds.

#### Processing Request using Inbound Lua Filters

You can actually add the custom business logic in envoy filter using [Lua filter](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/service-mesh/envoyfilter.yaml#L143).  

```
  inline_code: |
    function envoy_on_request(request_handle)
      local meta = request_handle:streamInfo():dynamicMetadata()
      for key, value in pairs(meta) do
        request_handle:headers():add("Header-You-need", value.jwt_payload.unique_name or value.jwt_payload.preferred_username or value.jwt_payload.sub)
      end
    end
```

* This lua filter adds the required header in the request for the user calling the API so that developers dont have to do this on their own. You can do any pre processing.

#### Adding JWT token for all outbound request

As we dont want our developers to write any security logic in their code and we also have enabled JWT validation for all in inbound reuest, we can add a [lua filter](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/service-mesh/envoyfilter.yaml#L164), that would add client credential JWT token for every outbound request intended for the apps that we care about. 

```
    function envoy_on_request(request_handle)
      local host = request_handle:headers():get(":authority")
      request_handle:logCritical("hostname is " .. host)
      if host:match("path for which the token should be issued") then
        if oauth2_token and oauth2_token_expiry and oauth2_token_expiry > os.time() then
          if count then
            count = count + 1
            request_handle:logCritical("using existing " .. tostring(count))
          end
          request_handle:headers():add("Authorization", "Bearer " .. oauth2_token)
```
* This intercepts all the outbound request and checks if the host is of type let's say ```somesvc.namespace.cluster.local```
* It also verifies if the token is expired as it would trigger a new oauth2 flow

```
  oauth2_token_expiry = os.time() + 2700 -- the expiry of the token for your IDP
  local request_headers = {
      [":method"] = "POST",
      [":authority"] = "authority",
      [":path"] = "the path to do client credentials flow",
      ["content-type"] = "application/x-www-form-urlencoded"
  }
  local payload = {
     grant_type = "client_credentials",
     client_id = "client-id",
     client_secret = "client-secret",
     scope = "some-scope"
  }
  local payload_query = ""
  for key, value in pairs(payload) do
    payload_query = payload_query .. key .. "=" .. value .. "&"
  end
  payload_query = string.sub(payload_query, 1, -2) -- Remove the trailing "&"
  -- the log level is critical set for istio envoy, you have to set while setting up the istio to enable other log levels
  -- request_handle:logCritical("The payload before"..payload_query)
  local response_headers, body = request_handle:httpCall(
    "ms_jwks_cluster",
    request_headers,
    payload_query,
    5000
  )
  if response_headers and body then
    local startIndex, endIndex = body:find('"access_token":"(.-)"')
    oauth2_token = body:sub(startIndex + 16, endIndex - 1)
  end
  request_handle:headers():add("Authorization", "Bearer " .. oauth2_token)
```
* If the new token is to be requested the payload is created to make a client credentials flow
* the secrets can be either used via an ENV variable or istios Secret discovery service or string interpolation at runtime
* the new expiry is set, the token is requested and added to the outbound request
* Envoyfilter that is added as side car to the intended outbound app, would do the same process to verify and decide what to do.

#### Extneral Authorization using OPA


## References

- istio dataplane : https://istio.io/v1.14/blog/2019/data-plane-setup/
- Packet Routing : https://jimmysong.io/en/blog/understanding-how-envoy-sidecar-intercept-and-route-traffic-in-istio-service-mesh/
- Packet Routing : https://jimmysongio.medium.com/sidecar-injection-transparent-traffic-hijacking-and-routing-process-in-istio-explained-in-detail-d53e244e0348
- Extending Envoy : https://istio.io/latest/docs/reference/config/networking/envoy-filter/
- Envoy http filter : https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/http_filters