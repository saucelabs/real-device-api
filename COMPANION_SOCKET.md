# Real-Time Insights: Mastering the Companion Socket

When running automated tests or manual sessions on the Sauce Labs Real Device Cloud via the API, you aren't working in a black box. The Companion Socket is a powerful, real-time WebSocket feed that streams everything happening on your device—device system logs, Appium server logs, and even network traffic—the moment it happens.

Instead of waiting for a test to finish to download a massive log file, you can tap into this stream to debug issues live, monitor performance, or trigger events in your own infrastructure based on device state.

This guide explains how to connect to the stream and how to isolate the specific logs you need.

## 1. Connecting to the Stream
The Companion Socket is available for every active device session. You can connect to it using any WebSocket client, but we recommend websocat for its simplicity and power on the command line.

### Prerequisites
- ***Active Session:*** You must have an active session ID (Android or iOS).
- ***Auth Token:*** Your Sauce Labs `username:accessKey` encoded in Base64.

### The Connection Command
We recommend increasing the buffer size (-B) to handle large data frames, such as network logs.

```shell
# 1. Set up your variables
SESSION_ID="your_session_id_here"
DATA_CENTER="us-west-1" # or eu-central-1, us-east-4
AUTH_TOKEN=$(echo -n "username:access_key" | base64)

# 2. Connect!
# The -B 2000000 flag increases the buffer to ~2MB to prevent crashes on large network logs.
websocat -H="Authorization: Basic $AUTH_TOKEN" "wss://api.${DATA_CENTER}.saucelabs.com/rdc/v2/socket/companion/${SESSION_ID}" | jq
```
## 2. Streaming Device Logs
***Type:*** `device.log.message`

These are the system logs from the device itself (Android Logcat or iOS Syslog). This is essential for catching app crashes, stack traces, or seeing custom logging statements your developers left in the app code.

***Command:***
```shell
websocat ... | jq --unbuffered 'select(.type == "device.log.message")'
```
***Sample Output:***
```json
{
  "tag": "app_process",
  "message": "Background concurrent copying GC freed 107MB...",
  "type": "device.log.message",
  "level": "INFO",
  "timestamp": "2025-11-21 03:07:26.985"
}
```

## 3. Streaming Appium Logs
***Type:*** `appium.log.message`

If you started an Appium server for your session, these logs stream directly from that server. Use this to debug why a specific automation command (like `click` or `findElement`) failed, or to see the raw WebDriver protocol communication.

***Command:***
```shell
websocat ... | jq --unbuffered 'select(.type == "appium.log.message")'
```

## 4. Streaming Network Traffic (HAR)
***Type:*** `device.har.entry`

You can capture HTTP/HTTPS traffic (API calls, image loads, analytics) in real-time. Unlike other logs, network capture is off by default to save resources.

***Step 1: Enable Network Capture***
Send a POST request to the API to start capturing traffic.
```shell
curl -X POST -u $AUTH "$BASE_URL/sessions/$SESSION_ID/device/enableNetworkCapture"
```
***Step 2: Filter for Network Entries***
Now that capture is enabled, filter the socket for HAR entries.
```shell
websocat ... | jq --unbuffered 'select(.type == "device.har.entry")'
```

***Step 3: Disable Network Capture***
When done, stop the capture to reduce noise and overhead.
```shell
curl -X POST -u $AUTH "$BASE_URL/sessions/$SESSION_ID/device/disableNetworkCapture"
```

## Pro Tip: Capture Everything at Once
You don't have to choose one log type. You can watch the stream live and automatically sort messages into separate files (`device_log.json`, `appium_log.json`, and `network_log.json`) simultaneously.

This uses `tee` and process substitution to split the stream:
```shell
websocat -B 2000000 -H="Authorization: Basic $AUTH_TOKEN" \
  "wss://api.${DATA_CENTER}.saucelabs.com/rdc/v2/socket/companion/$SESSION_ID" | \
  tee \
    >(jq --unbuffered 'select(.type=="device.log.message")' > device_log.json) \
    >(jq --unbuffered 'select(.type=="appium.log.message")' > appium_log.json) \
    >(jq --unbuffered 'select(.type=="device.har.entry")' > network_log.json) \
  | jq --unbuffered '.' # Optional: Print everything to screen as well
```