## Introduction


This is the second part of the series which also focuses on passwordless access to AWS resources with external Identity provider as the issuer. Now this may seem a litte overhead and redundant for K8s enabled environment but works fairly well for non K8s based orchestrators where kubelet does not help with token refresh on your behalf. In this blog we are still leveraging k8s as our deployer but the concept remains the same and we can attach the side car (responsible for rotation of our secrets) to the main application code.

It's going to be a short blog and would only be going over items different from previous scenario


## Why we need a side car now and an external IDP? 

Let's deep dive into the explanation, in case of on prem kubernetes, it's the responsibility of kubelet to grab and refresh the token, what would happen if that's not the case

* We are using an other orchestrator where the daemon can not get the token for us, let alone refresh
* Kubernetes is an old version and does not support the Issuer feature
* Too afraid to take chances and mess up the API server :D (Believe me , i got my whole cluster down trying the previous one hence strict and ordered instructions given)

## How does the side car gets injected and what it does?

Sidecar is injected the same way env variables are injected in the previous post, using mutating webhooks. [mutating_webhook.py](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/webidentity-webhook-external-idp/mutating_webhook/mutating_webhook.py#L10) adds the side car, and also adds the environment vairables *CLIENT_ID*, *CLIENT_SECRET* & *SCOPE* .

The [webidentity_sidecar.sh](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/webidentity-webhook-external-idp/webidentity_sidecar/get_token.sh) uses those environment variables to the Oauth2 flow using [Client Credentials Flow]("Oauth2 Flow used for backend system where we can trust to put our secrets") and grab the token and does that [every 50 minutes](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/webidentity-webhook-external-idp/webidentity_sidecar/Dockerfile#L5)

## How does my IAM Role and Trust relationship looks like?

AWS resources would similar with only change being the issuer, in this case it would be Azure or any IDP you have. Grab the token using curl and grab the issuer

```
curl -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "scope=https://graph.microsoft.com/.default" \
  -d "client_secret=YOUR_CLIENT_SECRET" \
  -d "grant_type=client_credentials" \
  "https://login.microsoftonline.com/YOUR_TENANT_ID/oauth2/v2.0/token"
``` 

put the token in [jwt.io](https://jwt.io) and grab the issuer and put it in AWS, same way as explained in first section

## Enhancements & Next Steps

Would add detailed information and how to steps if need be and as per feedback as mostly it's same as previous one
