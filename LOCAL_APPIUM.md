# Local Appium over OpenAPI

## Introduction
Although we encourage using [our hosted Appium solution](https://docs.saucelabs.com/mobile-apps/automated-testing/appium/), for some usecases it can be beneficial to run Appium locally. This guide is a sample on how to connect a local appium-server to our remote Android and iOS devices.

## Technical specification

Appium requires a local ADB connection for Android devices, and a WDA forward for iOS.

### Android

In order to get a local ADB connection, we need to start an OpenAPI session as usual and then use the returned `vusbUrl` link from the session information to forward the ADB from the device.

#### Example workflow

1. Start a session

```
POST /sessions
```

```
{
  "device" : {
    "os" : "android"
  }
}
```

2. Get `vusbUrl` link

Wait for the session to stabilize then:

```
GET /sessions/{session_id}
```

Fetch the websocket URL in `links -> vusbUrl`

3. Establish an adb proxy between your local machine and our remote device

You can use a tool like `websocat` to achieve this, using basic auth and passing the `sessionId` header with the openAPI session id. The `vusbUrl` points to a websocket connection that encapsulates a binary adb connection to the device. Please take a look at our example [api-connect script](#Example script) for more information.

### iOS

For iOS, our solution consist in mounting the endpoint of the WebDriverAgent running in the device in a local port. This is possible leveraging the http forward endpoints in the OpenAPI

#### Example workflow

1. Start a session

```
POST /sessions
```

```
{
  "device" : {
    "os" : "android"
  }
}
```

2. Wait for the session to be established

Check the state is `ACTIVE` in

```
GET /sessions/{session_id}
```

3. Forward the WDA port

Our OpenAPI solution exposes an http proxy endpoint running in the device. Appium needs a WDA server listening in the localhost interface to connect with it using the http protocol. To achieve this, we run locally a reverse proxy to our http proxy endpoint that:
* Handles the basic auth in OpenAPI
* Converts the SSL encrypted https messages to plain http
* Rewrites the request path so that the WDA endpoint is exposed in the root path


There are several tools to achieve this. Our reference implementation script uses [Caddy](https://caddyserver.com/). The endpoint that the http calls need to be forwarded to is

```
/sessions/{session_id}//device/proxy/http/localhost/8100
```

## Example script

We prepared the [api-connect script](scripts/api-connect.sh) as a reference implementation on how to achieve this.

### Requirements

In order for the script to run properly, you'll need the following tools installed locally:

* `curl`
* `jq`
* `websocat` (Android only)
* `adb` (Android only)
* `docker` (iOS only)

### Usage

You'll need the following environment variables set:

* `SAUCE_USERNAME`: Your SauceLabs user.
* `SAUCE_ACCESS_KEY`: Your SauceLabs api access key.
* `SAUCE_API_URL`: The OpenAPI URL. Depending on the environment can be one of
    * https://api.us-west-1.saucelabs.com
    * https://api.eu-central-1.saucelabs.com
    * https://api.us-east-4.saucelabs.com

```
api-connect <sessionId>
```

Simply provide a established OpenAPI sessionId and depending on the device OS it will:

1. For iOS: Starts a local [Caddy](https://caddyserver.com/) that exposes the WDA endpoint in local port `8100`. You'll need then to pass the `webDriverAgentUrl` capability to your local Appium server pointing to this port on your loopback interface.
2. For Android: Forwards the device ADB connection to local port `50371` (can be modified in the script) and starts an ADB server connecting to this port.