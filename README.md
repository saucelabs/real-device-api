# Real Device Access API v2
> This API is currently under active development and is subject to change. Access is currently restricted to early adopters. If you would like access please get in contact with you Sauce Labs representative.

This repository contains documentation for the Sauce Labs Real Device API. This API provides remote access to our pool of real devices, allowing you to automate them using the provided HTTP and WebSocket interfaces.


## Overview
The API consists of:
- **HTTP API:** For session management and most device interactions.
- **WebSocket API:** For streaming live device data, such as logs, screen recordings, and network traffic.

## HTTP API
The HTTP API is used for creating and managing device sessions, as well as performing certain device operations. Full details are available in the [RDC Access API specification](open_api_specification.yaml).

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

## Getting Started

For detailed usage examples and a step-by-step guide to interacting with the Sauce Labs Read Devices Access API v2, 
please see our [Integration Guide](INTEGRATION_GUIDE.md).

## Local Appium

For a quick start running Appium locally, please follow [our guide](./LOCAL_APPIUM.md) on the topic.

## Sauce Lab's Hosted Appium Server

Use your devices more efficiently and decrease the runtime of your Appium test suite. Our RDC Access API lets you reserve a device
**once** and run tests back-to-back, cutting out repetitive setup and wait times.

For a quick start, please see **[Faster, Smarter Appium Testing with RDC Access API Sessions.](./SAUCE_LABS_HOSTED_APPIUM.md)**.
