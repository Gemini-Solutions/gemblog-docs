## Introduction

We have achieved passwordless access using orchestrator , but in this section we'd use webidentity and an external Identity Provider (Azure AD in our case) for local development. The problem statement is still the same, we dont want to distribute the access keys for accessing AWS resources and have the exact same configuration and source code for all our environments.

## What options do we have?

We can leverage webidentity and establish the trust relationship between our IDP and the AWS, wherein we have the token issued from our IDP and AWS trust the token. But which authorization grant to be used here. Let's evaluate

* authorization code grant : This can NOT be used as there's no actual browser to handle our authorization flow
* client credentials flow : This seems like a promising solution, and is used for machine to machine communication, but we then have the chicken and egg problem as to where to store these client id and secret and users might have these committed in their source code. If someone grabs these secrets they can access AWS resources.
* device flow : This is authorization code grant in absence of a browser. Let's evaluate this a bit more.

## What & Why of Device Flow

[Device flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code) is used for user authN/authZ where a browser is not present, example logging into netflix on your TV device. We can use same principal for our use case where users need not store any secrets and the active session in their browser (we said it does not exist but we mean browser on a different device :D). Here's the request flow

![Device Flow](./assets/webidentity-local/device%20flow.png)

* A cli (browser less) entity makes a device flow call from the client and the requested scope.
* IDP inturn returns the random string that would be used in subsequent calls to exchange the token
* User accesses the link given by script and enters the code and grabs the token from the script's stdout

## Setting up the App in Azure AD

We are taking Azure AD as example, but this can work with any IDP out there. As you are working with an app, the app would already be registered with Azure AD. 

* Create an app if not already configured/registered with Azure
* Ensure that app can do device flow. In manage app registeration section for your app -> Authentication -> Advanced Settings -> Enable button.
* Get yourself added to a AD security group for which the trust relationship is to be established.
* You might also want to add group claims in ```Token Configuration``` section
* Add a custom scope in ```Expose an API``` section in registered app in Azure AD.
* Get the scope which would be of type ```api://app-id/scope```
* keep app id and scope handy.

## Setting up IAM role in AWS

* Create an IAM role ```appname-local-webidentity-role``` with custom trust policy where appname identifies your app and matches that of in azure for consistency.

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "Azure AD JWKS key"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "sts.windows.net/1122334455/:sub": "JWT-sub-claim",
                    "sts.windows.net/1122334455/:groups": "s3-access-group",
                }
            }
        }
    ]
}
```

* In the Condition section add claim that serves your purpose, either by audience or security groups.
* Add least required permissions to the role and ensure that they are not giving permission to any prod resource.

## How to grab the token

* Once the application has been setup in Azure AD and IAM role been created, grab [devce_flow.sh](https://github.com/Gemini-Solutions/gemblog-codestub/blob/master/webidentity-local-aws-device-flow/device_flow.sh). It needs ```jq``` but you can manage it and it to path variable
* Run the script ```./device_flow.sh <app/client id> "<api://<appid>/<custom-scope-created>>"```.  There are two paramteres 1st being the app id and other being the scope created in the setup phase.
* Do as instructed on the cli, going over to ```https://microsoft.com/devicelogin``` and adding the code and grab the token

## How to access AWS resources

Once the token has been created, we can use AWS SDKs to access AWS resources and all we need to do is setup two environment variables

* ```AWS_ROLE_ARN``` the arn for the role that SDK would assume to access AWS resource.
* ```AWS_WEB_IDENTITY_TOKEN_FILE``` path of the file that has the token grabbed from previous step.

YOU ARE GOOD TO GO!!!!
