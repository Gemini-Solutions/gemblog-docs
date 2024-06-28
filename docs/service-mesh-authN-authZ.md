## Introduction

This is the second part of the series where [first](service-mesh.md) explains how service meshes work and this one focusses solely on extending envoy filter for JWT authentication and authorization based off OPA.

## What is Istio-proxy

Once the [init container](./service-mesh.md/#what-is-init-container) is done modifying the IP table routes, the envoy proxy is attached and does all the magic. Envoy/Istio proxy small-footprint edge and service proxy which is written in C++ , developed by folks at Lyft. It's the envoy proxy which is capable of doing everything and more discussed [here](./service-mesh.md#what-is-a-service-mesh)

## Extending Envoy's Capabilities using Istio Envoy Filter

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

the [rules section](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/service-mesh/envoyfilter.yaml#L100) dictate if the JWT filter should be applied to a path or not, here's a sample match 

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

              if host:match("%.svc%.cluster%.local") then
                request_handle:logCritical("outbound query")

                if oauth2_token_table and next(oauth2_token_table) ~= nil and oauth2_token_table["exp"] > os.time() then
                  request_handle:logCritical("inside if, token exp " .. tostring(oauth2_token_table["exp"]) .. " And token is" .. oauth2_token_table["token"])
                  if count then
                    count = count + 1
                    request_handle:logCritical("using existing " .. tostring(count))
                  end
                  request_handle:headers():add("Authorization", "Bearer " .. oauth2_token_table["token"])  
```
* This intercepts all the outbound request and checks if the host is of type let's say ```somesvc.namespace.cluster.local```
* It also verifies if the token is expired as it would trigger a new oauth2 flow

```
                  count = 0
                  oauth2_token_table  = { exp = os.time() + 2700} -- the expiry of the token for your IDP
                  local request_headers = {
                      [":method"] = "POST",
                      [":authority"] = "login.microsoftonline.com",
                      [":path"] = "/tenant-id/oauth2/v2.0/token",
                      ["content-type"] = "application/x-www-form-urlencoded"
                  }
                  local payload = {
                     grant_type = "client_credentials",
                     client_id = "client-id",
                     client_secret = "client-secret",
                     scope = "api:some-scope.default"
                  }

                  local payload_query = ""

                  for key, value in pairs(payload) do
                    payload_query = payload_query .. key .. "=" .. value .. "&"
                  end
                  payload_query = string.sub(payload_query, 1, -2) -- Remove the trailing "&"

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
                  request_handle:logCritical("Inside else got new token " .. oauth2_token)
                  oauth2_token_table["token"] = oauth2_token
```
* If the new token is to be requested the payload is created to make a client credentials flow
* the secrets can be either used via an ENV variable or istios Secret discovery service or string interpolation at runtime
* the new expiry is set, the token is requested and added to the outbound request
* Envoyfilter that is added as side car to the intended outbound app, would do the same process to verify and decide what to do.

#### Extneral Authorization using OPA

Now that we have established the JWT authentication for inbound and JWT creation for an intra cluster communication, every single endpoint is authenticated, but that's not it we need to ensure that only the authorized users can access an endponit. Let's say Jhon and Macy must be authenticated to payroll system but they should not be able to view each other's payroll. There are several ways to achieve this and one being [Open Policy Agent](https://www.openpolicyagent.org/). Envoy has yet another filter , [external authorization](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/service-mesh/envoyfilter.yaml#L226) for the same.

```
    grpc_service:
      google_grpc:
        stat_prefix: ext_authz
        target_uri: 10.97.100.26:9191
    status_on_error:
      code: ServiceUnavailable
    transport_api_version: V3
    with_request_body:
      allow_partial_message: true
      max_request_bytes: 8192
      pack_as_bytes: true
```

* It tells envoy that the external authorization system works by exposing the gRPC server.
* The Host IP where the actual authorization server hosted
* status on error, spews out a default message in case of error from the opa server itself
* pack as bytes boolean is used for multipart files or binary data upload to APIs.


## Setting up OPA server & Why's of gRPC for ext_authz

OPA server is run as the kubernetes [deployment](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/service-mesh/opa-deployment.yaml). We are using the istio flavor for OPA which exposes the gRPC server. OPA has bunch of policies written in rego and the user evaluates the input in json format against the policy. OPA is a mere policy enginer which just evaluates the policy and spews out the result and it's the client who can take decisions basis the results.To understand why we are using gRPC based communication between Envoy and OPA, let's take an example. The request is allowed iff the api is /public and is GET.

Here's a sample rego policy.

```
example.rego

package example

default allow = false

allow {
  input.method == "GET"
  input.path == "/public"
}

```

Here's the input.json against which the policy has to be evaluated

```
{
  "method": "GET",
  "path": "/public"
}
```

to evaluate the policy we have ```curl -X POST http://localhost:8181/v1/data/example/allow -d @input.json``` . Considering policy has already been uploaded to the server. But imagine we have to send a POST request to OPA server for evaluation in the required format for each and every request (GET, PUT, DELETE..), let's say user is making a simple GET request, we'd have to construct the payload as shown above ```"method": "GET", "path":"/pubilic"``` and make a POST request to opa server for evaluation. This is not feasible as we need to have all the attributes associated to the request, all the headers, user, paramters, path vairables, request variables etc.. The gRPC flavor for ext_authz comes to the rescue, it does everything that we need and uses POST for communication. It floods the payload with all the information associated to an incoming request, send it to OPA server and gets back the result in format where envoy either allows or denies the request.


## What's Next..?

We have enabled authN/authZ by abstracting all the logic out of the application code and extended envoy and OPA for the same. Explaining and writing rego policies is beyond the scope of this guide, but do check out in the following blogs where we outline how to better manage a rego repo structure, leverage bundles and evaluation basis external dynamic data.



## References

- [istio dataplane](https://istio.io/v1.14/blog/2019/data-plane-setup/)
- [Packet Routing 1](https://jimmysong.io/en/blog/understanding-how-envoy-sidecar-intercept-and-route-traffic-in-istio-service-mesh/)
- [Packet Routing 2](https://jimmysongio.medium.com/sidecar-injection-transparent-traffic-hijacking-and-routing-process-in-istio-explained-in-detail-d53e244e0348)
- [Extending Envoy](https://istio.io/latest/docs/reference/config/networking/envoy-filter/)
- [Envoy http filter](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/http_filters)

## NOTE (outbound request)

As envoy use lua filter and the disclaimer [here](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/lua_filter). our old approach of using the global variables for token and expiry backfired as let's say after certain time there are multiple pair or tokens and the expiries in global variables, but when the filer loaded, it randomly picked the oauth2 token and the expiry variable which often was not in sync with the real exp of the token in payload (exp claim), it was way off by hours. To rectify this we are using hashmap (table in lua) to tightly couple the token and it's expiry. Also lua only expose the function base64encode and not decode (maye coz of secuirty reasons) [here](https://github.com/envoyproxy/envoy/blob/main/source/extensions/filters/http/lua/lua_filter.h#L187). Had lua exposed the base64 decode function we could simply decode the token , get it's exp claim and follow the process as is.
