# Real Device API
> This API is currently under active development and is subject to change.

This repository contains documentation for the Sauce Labs Real Device API. This API provides remote access to our pool of real devices, allowing you to automate and automate them using the provided HTTP and WebSocket interfaces.


## Overview
The API consists of:
- **HTTP API:** For session management and most device interactions.
- **WebSocket API:** For streaming live device data, such as logs, screen recordings, and network traffic.

## HTTP API
The HTTP API is used for creating and managing device sessions, as well as performing certain device operations. Full details are available in the [OpenAPI specification](open_api_specification.yaml).

## WebSocket API
The WebSocket API provides real-time streams of data from your device sessions. There are two primary WebSocket endpoints:

### AlternativeIO Socket
- **Purpose:** Streams live screen recordings from your device session.
- **Data format:** Each message is a screenshot in MJPEG format.
- **Usage:** Connect to this socket to receive a continuous stream of device screenshots for monitoring or recording purposes.

### Companion Socket
- **Purpose:** Streams device logs and other real-time device events.
- **Data format:** JSON messages. Each message includes a `type` field to distinguish between log messages and other events.
- **Usage:** Connect to this socket to receive live logs and event notifications from your device session.

#### Example: Log Message
```json
{
    "type":"device.log.message",
    "processId":876,
    "level":"INFO",
    "timestamp":"2025-05-07 18:11:20.000",
    "message":"2025-05-07 18:11:20.000 INFO: trustd(libxpc.dylib)[..]"
}
```

# Usage Example: Real Device API

The Real Device API allows you to programmatically interact with real mobile devices in the Sauce Labs cloud 
for your testing purposes. This guide provides the information you need to get started with checking device status, 
creating and managing test sessions, and streaming logs.

## Base URLs
Sauce Labs offers three production environments for the Real Device Cloud (RDC) API. Please use the base URL that corresponds to your account's data center:
* US West: https://api.us-west-1.saucelabs.com/rdc/v2/
* EU Central: https://api.eu-central-1.saucelabs.com/rdc/v2/
* US East: https://api.us-east-4.saucelabs.com/rdc/v2/

```shell
export BASE_URL="https://api.us-west-1.saucelabs.com/rdc/v2"
```

In the examples below, we will use `$BASE_URL` as a placeholder.

## Authentication
The API uses Basic Authentication. You will need your Sauce Labs username and access key to make requests. 
You can find these in the `Account -> User Settings` section of the Sauce Labs UI.

All examples use curl and expect you to replace `YOUR_USERNAME` and `YOUR_ACCESS_KEY` with your credentials.
```shell
curl -u "YOUR_USERNAME:YOUR_ACCESS_KEY" \
  "$BASE_URL/devices/status"
```

## Quick Start Examples

### Check Device Status
You can retrieve a list of all available real devices and filter them based on various criteria.

#### List All Devices
```shell
curl -X GET \
  -u "YOUR_USERNAME:YOUR_ACCESS_KEY" \
  "$BASE_URL/devices/status"
```

#### Device Filtering Options
The `/devices/status` endpoint supports the following query parameters for filtering:

- `state`: Filter by device status. Possible values: `AVAILABLE`, `IN_USE`, `CLEANING`, `REBOOTING`, `MAINTENANCE`, `OFFLINE`.
- `privateOnly`: Set to `true` to show only your account's private devices.
- `deviceId`:  Filter by a device identifier. This field supports regular expressions (e.g., `iPhone.*`).

#### Examples:
```shell
# Get all devices
curl -X GET \
  -u "YOUR_USERNAME:YOUR_ACCESS_KEY" \
  "$BASE_URL/devices/status"

# Filter by device state
curl -X GET \
  -u "YOUR_USERNAME:YOUR_ACCESS_KEY" \
  "$BASE_URL/devices/status?state=AVAILABLE"

# Show only private devices
curl -X GET \
  -u "YOUR_USERNAME:YOUR_ACCESS_KEY" \
  "$BASE_URL/devices/status?privateOnly=true"

# Filter by device identifier (supports regex patterns)
curl -X GET \
  -u "YOUR_USERNAME:YOUR_ACCESS_KEY" \
  "$BASE_URL/devices/status?deviceId=iPhone.*"

# Combine multiple filters
curl -X GET \
  -u "YOUR_USERNAME:YOUR_ACCESS_KEY" \
  "$BASE_URL/devices/status?state=AVAILABLE&privateOnly=true&deviceId=iPhone.*"
```

#### Example Response

```json
{
  "devices": [
    {
      "descriptor": "iPhone_13_real",
      "isPrivateDevice": true,
      "status": "AVAILABLE"
    },
    {
      "descriptor": "Samsung_Galaxy_S21_real",
      "isPrivateDevice": false,
      "status": "IN_USE",
      "inUseBy": [
        {
          "username": "john.smith"
        }
      ]
    }
  ]
}
```

### Create a Device Session
To start a new testing session, you need to make a `POST` request to the `/sessions` endpoint.
> ***Note:*** The `deviceId` and `os` parameters in the request body are optional. If they are omitted, Sauce Labs will automatically select an available device for your session.

#### Example
```shell
curl -X POST \
  -u "YOUR_USERNAME:YOUR_ACCESS_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "device": {
      "deviceId": "iPhone_16_real",
      "os": "ios"
    }
  }' \
  "$BASE_URL/sessions"
```

#### Example Response

```json
{
  "id": "{session_id}",
  "status": "PENDING",
  "links": null,
  "device": null,
  "error": null
}
```

### Manage Device Sessions
Once a session is created, you can list your sessions, get details for a specific session, and close it when you are done.

#### List All Sessions
You can filter sessions by `status` and `deviceId.`

##### Session Filtering Options
The `/sessions` endpoint supports the following filters:

- `status`: Filter by session status
  * `PENDING` - Session is waiting to be created
  * `CREATING` - Session is being set up
  * `ACTIVE` - Session is ready for interaction
  * `CLOSING` - Session is being terminated
  * `CLOSED` - Session has ended
  * `ERRORED` - Session encountered an error

- `deviceId`: Filter by specific device identifier (e.g., iPhone_16_real, Samsung_Galaxy_S21_real, iPhone.*)

You can combine both filters to get more specific results, such as finding all active sessions on a particular device.

##### Examples 
```shell
# Get all sessions
curl -X GET \
  -u "YOUR_USERNAME:YOUR_ACCESS_KEY" \
  "$BASE_URL/sessions"

# Filter by session status
curl -X GET \
  -u "YOUR_USERNAME:YOUR_ACCESS_KEY" \
  "$BASE_URL/sessions?status=ACTIVE"

# Filter by device ID
curl -X GET \
  -u "YOUR_USERNAME:YOUR_ACCESS_KEY" \
  "$BASE_URL/sessions?deviceId=iPhone_16_real"

# Combine multiple filters - active sessions on specific device
curl -X GET \
  -u "YOUR_USERNAME:YOUR_ACCESS_KEY" \
  "$BASE_URL/sessions?status=ACTIVE&deviceId=iPhone_16_real"
```

##### Example Response 
```json
{
  "sessions": [
    {
      "sessionId": "123e4567-e89b-12d3-a456-426614174000",
      "status": "ACTIVE",
      "device": {
        "deviceDescriptorId": "Samsung_Galaxy_S8_real2",
        "deviceName": "Samsung Galaxy S8",
        "os": "ANDROID",
        "osVersion": "9",
        "resolutionWidth": 1440,
        "resolutionHeight": 2960,
        "screenSize": 5.7
      },
      "links": {
        "ioWebsocketUrl": "wss://api.saucelabs.com/rdc/v2/sessions/123e4567-e89b-12d3-a456-426614174000/wss/io",
        "eventsWebsocketUrl": "wss://api.saucelabs.com/rdc/v2/sessions/123e4567-e89b-12d3-a456-426614174000/wss/events",
        "self": "https://api.saucelabs.com/rdc/v2/sessions/123e4567-e89b-12d3-a456-426614174000"
      },
      "error": null
    }
  ]
}
```

#### Get Session Details
Retrieve information for a single session using its `SESSION_ID`.
```shell
curl -X GET \
  -u "YOUR_USERNAME:YOUR_ACCESS_KEY" \
  "$BASE_URL/sessions/{session_id}"
```

##### Example Response
```json
{
  "sessionId": "123e4567-e89b-12d3-a456-426614174000",
  "status": "ACTIVE",
  "device": {
    "deviceDescriptorId": "Samsung_Galaxy_S8_real2",
    "deviceName": "Samsung Galaxy S8",
    "os": "ANDROID",
    "osVersion": "9",
    "resolutionWidth": 1440,
    "resolutionHeight": 2960,
    "screenSize": 5.7
  },
  "links": {
    "ioWebsocketUrl": "wss://api.saucelabs.com/rdc/v2/sessions/123e4567-e89b-12d3-a456-426614174000/wss/io",
    "eventsWebsocketUrl": "wss://api.saucelabs.com/rdc/v2/sessions/123e4567-e89b-12d3-a456-426614174000/wss/events",
    "self": "https://api.saucelabs.com/rdc/v2/sessions/123e4567-e89b-12d3-a456-426614174000"
  },
  "error": null
}
```

#### Close a Session
Terminate a device session and release the device. When you close a session, its status will transition from `ACTIVE` → `CLOSING` → `CLOSED`.

##### Session Closure Options
The session closure endpoint provides flexible termination options:

- Basic Closure: Immediately terminates the session and releases the device
- Reboot Option: **Available only for private devices**, performs a complete device reboot after session closure

***Note:*** The `rebootDevice` parameter only works with private devices. Public/shared devices cannot be rebooted through the API.

##### Examples 
```shell
# Basic session termination
curl -X DELETE \
  -u "YOUR_USERNAME:YOUR_ACCESS_KEY" \
  $BASE_URL/sessions/123e4567-e89b-12d3-a456-426614174000

# Close session with device reboot (private devices only)
curl -X DELETE \
  -u "YOUR_USERNAME:YOUR_ACCESS_KEY" \
  "$BASE_URL/sessions/123e4567-e89b-12d3-a456-426614174000?rebootDevice=true"
```

##### Example Response
```yaml
{
  "id": "f64b3cc1-7c56-42b5-bb59-d31711337ce9",
  "status": "CLOSING",
  "links": {
    "ioWebsocketUrl": "wss://api.staging.saucelabs.net/rdc/v2/socket/alternativeIo/0501a5ee-76e1-4b1e-8302-82379025a275",
    "eventsWebsocketUrl": "wss://api.staging.saucelabs.net/rdc/v2/socket/companion/0501a5ee-76e1-4b1e-8302-82379025a275",
    "deviceUrl": null,
    "self": "https://api.staging.saucelabs.net/rdc/v2/sessions/f64b3cc1-7c56-42b5-bb59-d31711337ce9"
  },
  "device": {
    "deviceDescriptorId": "Samsung_Galaxy_S8_real2",
    "deviceName": "Samsung Galaxy S8",
    "os": "ANDROID",
    "osVersion": "9",
    "resolutionWidth": 1440,
    "resolutionHeight": 2960,
    "screenSize": 5.7
  },
  "error": null
}
```

### WebSocket for Live Event Streaming
You can connect to a WebSocket to receive real-time logs and events from an active session.

***Prerequisites:***
- Active device session (status must be `ACTIVE`)
- The `eventsWebsocketUrl` from the session details response.
- A WebSocket client tool like `websocat` or `wscat`.

#### Live Streaming with websocat (Recommended)
`websocat` is a versatile command-line client for WebSockets.

##### Installation:
```shell
# macOS (Homebrew)
brew install websocat

# For other systems, see: https://github.com/vi/websocat/releases
```

##### Usage:

```shell
# Set your credentials and session ID
USERNAME="YOUR_USERNAME"
ACCESS_KEY="YOUR_ACCESS_KEY"
SESSION_ID="YOUR_SESSION_ID"
DATA_CENTER="us-west-1" # or eu-central-1, us-east-4


# Generate a Base64 authentication token
AUTH_TOKEN=$(echo -n "$USERNAME:$ACCESS_KEY" | base64)

echo "Auth token: $AUTH_TOKEN"

# Connect to the WebSocket
websocat -H="Authorization: Basic $AUTH_TOKEN" "wss://api.${DATA_CENTER}.saucelabs.com/rdc/v2/socket/companion/${SESSION_ID}"
```

#### Alternative Tool: wscat (Node.js)
If you have Node.js installed, you can use wscat.

##### Installation:
```shell
# Install wscat globally
npm install -g wscat
```

##### Usage: 

```shell
# Set your credentials and session ID
USERNAME="YOUR_USERNAME"
ACCESS_KEY="YOUR_ACCESS_KEY"
SESSION_ID="YOUR_SESSION_ID"
DATA_CENTER="us-west-1" # or eu-central-1, us-east-4

# Generate a Base64 authentication token
AUTH_TOKEN=$(echo -n "$USERNAME:$ACCESS_KEY" | base64)

echo "Auth token: $AUTH_TOKEN"

# Connect to the WebSocket
wscat -c "wss://api.${DATA_CENTER}.saucelabs.net/rdc/v2/socket/companion/$SESSION_ID" \
  -H "Authorization: Basic $AUTH_TOKEN"
```