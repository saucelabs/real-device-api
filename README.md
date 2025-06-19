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

The Real Device API allows you to interact with real mobile devices for testing purposes. This API provides endpoints to check device status, create sessions, and interact with devices.

## Base URLs
Sauce Labs offers 3 production environments:
* US West: https://api.us-west-1.saucelabs.com/rdc/v2/
* EU Central: https://api.eu-central-1.saucelabs.com/rdc/v2/
* US East: https://api.us-east-4.saucelabs.com/rdc/v2/

## Authentication
The API uses Basic Authentication with your username and access key:
```shell
curl -u "username:access_key" \
  https://api.us-west-1.saucelabs.com/rdc/v2/devices/status
```

## Quick Start Examples
### Check Device Status
Get the current status of all available devices with optional filtering:

```shell
# Get all devices
curl -X GET \
  -u "username:access_key" \
  https://api.us-west-1.saucelabs.com/rdc/v2/devices/status

# Filter by device state
curl -X GET \
  -u "username:access_key" \
  "https://api.us-west-1.saucelabs.com/rdc/v2/devices/status?state=AVAILABLE"

# Show only private devices
curl -X GET \
  -u "username:access_key" \
  "https://api.us-west-1.saucelabs.com/rdc/v2/devices/status?privateOnly=true"

# Filter by device identifier (supports regex patterns)
curl -X GET \
  -u "username:access_key" \
  "https://api.us-west-1.saucelabs.com/rdc/v2/devices/status?deviceId=iPhone.*"

# Combine multiple filters
curl -X GET \
  -u "username:access_key" \
  "https://api.us-west-1.saucelabs.com/rdc/v2/devices/status?state=AVAILABLE&privateOnly=true&deviceId=iPhone.*"
```
#### Device Filtering Options
The `/devices/status` endpoint now supports advanced filtering:

- `state`: Filter by device status (`AVAILABLE`, `IN_USE`, `CLEANING`, `REBOOTING`, `MAINTENANCE`, `OFFLINE`)
- `privateOnly`: Show only private devices for your account (`true`/`false`)
- `deviceId`: Filter by device identifier with regex support (e.g., iPhone.*, Samsung.*)

#### Response

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
Start a new session with a specific device:

```shell
curl -X POST \
  -u "username:access_key" \
  -H "Content-Type: application/json" \
  -d '{
    "device": {
      "deviceId": "iPhone_16_real",
      "os": "ios"
    }
  }' \
  https://api.us-west-1.saucelabs.com/rdc/v2/sessions
```
***Note:*** `deviceId` and `os` params in the session creating payload are optional. 

#### Response

```json
{
  "id": "{session_id}",
  "status": "PENDING",
  "links": null,
  "device": null,
  "error": null
}
```

### List All Sessions
Get all your device sessions with optional filtering:

```shell
# Get all sessions
curl -X GET \
  -u "username:access_key" \
  https://api.us-west-1.saucelabs.com/rdc/v2/sessions

# Filter by session status
curl -X GET \
  -u "username:access_key" \
  "https://api.us-west-1.saucelabs.com/rdc/v2/sessions?status=ACTIVE"

# Filter by device ID
curl -X GET \
  -u "username:access_key" \
  "https://api.us-west-1.saucelabs.com/rdc/v2/sessions?deviceId=iPhone_16_real"

# Combine multiple filters - active sessions on specific device
curl -X GET \
  -u "username:access_key" \
  "https://api.us-west-1.saucelabs.com/rdc/v2/sessions?status=ACTIVE&deviceId=iPhone_16_real"
```
#### Session Filtering Options
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

#### Response 
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

### Get Session Details
Retrieve information about a specific session:

```shell
curl -X GET \
  -u "username:access_key" \
  https://api.us-west-1.saucelabs.com/rdc/v2/sessions/{session_id}
```

#### Response
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

### Close a Session
Terminate a device session and release the device back to the available pool:

```shell
# Basic session termination
curl -X DELETE \
  -u "username:access_key" \
  https://api.us-west-1.saucelabs.com/rdc/v2/sessions/123e4567-e89b-12d3-a456-426614174000

# Close session with device reboot (private devices only)
curl -X DELETE \
  -u "username:access_key" \
  "https://api.us-west-1.saucelabs.com/rdc/v2/sessions/123e4567-e89b-12d3-a456-426614174000?rebootDevice=true"
```

#### Session Closure Options
The session closure endpoint provides flexible termination options:

- Basic Closure: Immediately terminates the session and releases the device
- Reboot Option: **Available only for private devices**, performs a complete device reboot after session closure

***Note:*** The `rebootDevice` parameter only works with private devices. Public/shared devices cannot be rebooted through the API.

#### Response 
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
The session transitions through these states:

* `ACTIVE` → `CLOSING` (immediate response)
* `CLOSING` → `CLOSED` (within seconds)




### WebSocket Connection for Live Logs
Connect to the events WebSocket to receive real-time logs :

***Prerequisites:***
- Active device session (status must be `ACTIVE`)
- Valid authentication credentials
- WebSocket URL from session details response

#### Testing Endpoint Availability (curl)
Use this to verify the WebSocket endpoint is accessible before establishing a persistent connection:

```shell
#!/bin/bash

USERNAME="your_username"
ACCESS_KEY="your_access_key"
SESSION_ID="session_id"

echo "Testing WebSocket endpoint..."
curl -i -N \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: $(openssl rand -base64 16)" \
  -u "$USERNAME:$ACCESS_KEY" \
  "https://api.us-west-1.saucelabs.com/rdc/v2/sessions/$SESSION_ID"
```

***Expected Response:*** HTTP 101 Switching Protocols indicates successful handshake.

***Note:*** curl only performs the WebSocket handshake test. It cannot maintain persistent connections for streaming logs.

#### Live Streaming with websocat (Recommended)
websocat provides the most reliable WebSocket client experience:

```shell
# Configuration
USERNAME="your_username"
ACCESS_KEY="your_access_key" 
SESSION_ID="your_session_id"

# Generate authentication token
AUTH_TOKEN=$(echo -n "$USERNAME:$ACCESS_KEY" | base64)

echo "Auth token: $AUTH_TOKEN"

# Then test the command
websocat -H="Authorization: Basic $AUTH_TOKEN" "wss://api.staging.saucelabs.net/rdc/v2/socket/companion/$SESSION_ID"
```
##### Installation:
```shell
# macOS (Homebrew)
brew install websocat

# Linux/Windows: Download from https://github.com/vi/websocat/releases
```

#### Alternative with wscat (Node.js)
If you prefer npm-based tools or websocat is unavailable:

```shell
# Configuration
USERNAME="your_username"
ACCESS_KEY="your_access_key" 
SESSION_ID="your_session_id"

# Generate authentication token
AUTH_TOKEN=$(echo -n "$USERNAME:$ACCESS_KEY" | base64)

echo "Auth token: $AUTH_TOKEN"

# Then test the command
wscat -c "wss://api.staging.saucelabs.net/rdc/v2/socket/companion/$SESSION_ID" \
  -H "Authorization: Basic $AUTH_TOKEN"
```

##### Installation: 
```shell
# Install wscat globally
npm install -g wscat
```