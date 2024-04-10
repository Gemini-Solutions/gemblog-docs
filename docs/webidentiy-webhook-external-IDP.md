## Introduction

This is the second part of the series which also focuses on passwordless access to AWS resources but with an external Identity provider as the issuer. Now this may seem a litte overhead and redundant for K8s enabled environment but works fairly well for non K8s based orchestrators. Though we are using kubernetes as our deployer in the blog but same concept can be applied elsewhere.

NOTE: Do refer to [first](/webidentiy-webhook-k8s-onprem/) part of the blog to get the detailed information. [Code ref](https://github.com/Gemini-Solutions/gemblog-codestub/tree/master/webidentity-webhook-external-idp)

## Why we need an external IDP?

Let's deep dive into the explanation, in case of on prem kubernetes, it's the responsibility of kubelet to grab and refresh the token from the K8s api server, but, what would happen if that's not the case

* We are using an orchestrator where the daemon/process can not get the token for us, let alone refresh
* Kubernetes is an old version and does not support the issuer feature
* Too afraid to take chances and mess up the API server :D (Believe me , I got my whole cluster down trying the previous one hence strict and ordered instructions given). As this setup does not require any changes being done to K8s server.

It is this external IDP that we need to grab the token and eastablish the trust relationship in AWS and IDP (in our case Azure. We'd be using Azure and IDP interchangeably).

## How everything works and why the side car?

Similar to previous section we inject some properties to the incoming request for POD creation but this time along with environment variables we add a side car, [webidentity_sidecar.sh](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/webidentity-webhook-external-idp/webidentity_sidecar/get_token.sh). It runs [every 50 minutes](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/webidentity-webhook-external-idp/webidentity_sidecar/Dockerfile#L5) and grab the token from the external IDP using [Client Credentials Flow]("Oauth2 Flow used for backend system where we can trust to put our secrets")

The setup also need the pair of [Secrets](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/webidentity-webhook-external-idp/test_app/secret.yaml) which would be used by side car to do the [client credentials flow](https://developer.okta.com/docs/guides/implement-grant-type/clientcreds/main/#about-the-client-credentials-grant)


## How does my IAM Role and Trust relationship looks like?

For setup refer [here](/webidentiy-webhook-k8s-onprem/#adding-identity-provider-and-role-for-the-pod)

The setup looks exactly same as previous one but with slight change to issuer. All the external IDP have a [discovery endpoint](https://connect2id.com/products/server/docs/api/discovery) use that to grab the details add issuer as identity provider in IAM. As these are publically available we also need not create the AWS API GW public endpoints.

*To grab the token*

```
curl -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "scope=https://graph.microsoft.com/.default" \
  -d "client_secret=YOUR_CLIENT_SECRET" \
  -d "grant_type=client_credentials" \
  "https://login.microsoftonline.com/YOUR_TENANT_ID/oauth2/v2.0/token"
``` 

put the token in [jwt.io](https://jwt.io) and grab the issuer from the token and add it as identity providers in IAM and keep appending the audience list as you onboard newer applications.

## Enhancements & Next Steps

Would add detailed information and how to steps if need be and as per feedback as mostly it's same as previous one
