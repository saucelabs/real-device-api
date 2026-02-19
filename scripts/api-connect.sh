#!/bin/bash
set -e

# --- Configuration ---
ADB_PORT=50371
WDA_PORT=8100
USBMUXD_SOCKET=/var/run/usbmuxd
USBMUXD_SOCKET_BACKUP=/var/run/usbmuxd.real

# --- Global variables for cleanup ---
websocat_pid=""
socat_pid=""
iproxy_pid=""
keepalive_pid=""
CADDY_CONTAINER_ID=""
WRAPPER=""
os=""
RESPONSE_FILE=$(mktemp)
KEEPALIVE_LOG=$(mktemp)

# --- Cleanup Function ---
quit() {
    local exit_code=${1:-0}
    echo
    echo "Exiting and cleaning up resources..."

    # --- Android Cleanup ---
    if [[ -n "$websocat_pid" ]] && kill -0 "$websocat_pid" 2>/dev/null; then
        echo "Stopping websocat process (PID: $websocat_pid)..."
        kill "$websocat_pid" 2>/dev/null || true
        adb disconnect localhost:$ADB_PORT 2>/dev/null || true
        echo "Websocat process stopped."
    fi

    # --- iOS usbmuxd bridge Cleanup ---
    if [[ -n "$keepalive_pid" ]] && kill -0 "$keepalive_pid" 2>/dev/null; then
        kill "$keepalive_pid" 2>/dev/null || true
    fi

    if [[ -n "$iproxy_pid" ]] && kill -0 "$iproxy_pid" 2>/dev/null; then
        echo "Stopping iproxy process (PID: $iproxy_pid)..."
        kill "$iproxy_pid" 2>/dev/null || true
    fi

    if [[ -n "$socat_pid" ]] && kill -0 "$socat_pid" 2>/dev/null; then
        echo "Stopping socat process (PID: $socat_pid)..."
        kill "$socat_pid" 2>/dev/null || true
        wait "$socat_pid" 2>/dev/null || true
    fi

    [[ -n "$WRAPPER" && -e "$WRAPPER" ]] && rm -f "$WRAPPER"

    if [[ -e "$USBMUXD_SOCKET_BACKUP" ]]; then
        rm -f "$USBMUXD_SOCKET"
        mv "$USBMUXD_SOCKET_BACKUP" "$USBMUXD_SOCKET"
        echo "Restored $USBMUXD_SOCKET"
    fi

    # --- iOS Caddy Cleanup ---
    if [[ -n "$CADDY_CONTAINER_ID" ]] && docker ps -q -f "id=${CADDY_CONTAINER_ID}" | grep -q .; then
        echo "Stopping Caddy container ($CADDY_CONTAINER_ID)..."
        docker stop "$CADDY_CONTAINER_ID" > /dev/null
        echo "Caddy container stopped."
    fi

    # --- General Cleanup ---
    rm -f "$RESPONSE_FILE"
    rm -f "$KEEPALIVE_LOG"

    trap - SIGINT SIGTERM
    exit "$exit_code"
}

handle_exit_signal() {
    echo
    echo "Signal received."
    quit 0
}

trap handle_exit_signal SIGINT SIGTERM


# --- Helper Functions ---
check_dependency() {
    local cmd=$1
    local package=${2:-$1}
    if ! command -v "$cmd" &>/dev/null; then
        echo "$package is not installed. Please install before using $0"
        quit 1
    fi
}

call_api() {
    local URL=$1
    local METHOD=${2:-GET}

    HTTP_CODE=$(curl -s -X "$METHOD" -u "$SAUCE_USERNAME:$SAUCE_ACCESS_KEY" \
        -o "$RESPONSE_FILE" -w "%{http_code}" "$URL")

    if [ "$HTTP_CODE" -ne 200 ]; then
        echo "Error HTTP $HTTP_CODE"
        cat "$RESPONSE_FILE" | jq .
        quit 1
    fi

    RESPONSE=$(cat "$RESPONSE_FILE")
}


# --- OS-Specific Handlers ---

handle_android() {
    check_dependency 'websocat'
    check_dependency 'adb'

    local wss_endpoint=$1
    local session_id=$2
    local auth_b64
    auth_b64=$(printf '%s:%s' "$SAUCE_USERNAME" "$SAUCE_ACCESS_KEY" | base64)

    websocat -b tcp-l:127.0.0.1:$ADB_PORT "$wss_endpoint" \
        -E -H "sessionId: $session_id" \
        -H "Authorization: Basic $auth_b64" &
    websocat_pid=$!
    sleep 1

    echo "websocat started with PID: $websocat_pid on port $ADB_PORT"
    adb connect localhost:$ADB_PORT
    echo "ADB connected! You can start your appium server with 'appium --allow-insecure chromedriver_autodownload'"

    cat <<EOF
Example capabilities:
{
  "platformName": "Android",
  "browserName": "Chrome",
  "appium:automationName": "UiAutomator2",
  "appium:uiautomator2ServerInstallTimeout": 180000,
  "appium:chromeOptions": {
    "w3c": true
  }
}
EOF
}

handle_ios() {
    local wss_endpoint=$1
    local session_id=$2

    if [[ $EUID -eq 0 ]]; then
        handle_ios_usbmuxd "$wss_endpoint" "$session_id"
    else
        echo "Not running as root — using Caddy reverse proxy for WDA-only access."
        echo "For full device access (Xcode, Instruments), re-run with: sudo $0 $SESSION"
        echo
        handle_ios_caddy "$session_id"
    fi
}

handle_ios_usbmuxd() {
    check_dependency 'socat'
    check_dependency 'websocat'
    check_dependency 'iproxy' 'libimobiledevice'

    local wss_endpoint=$1
    local session_id=$2
    local auth_b64
    auth_b64=$(printf '%s:%s' "$SAUCE_USERNAME" "$SAUCE_ACCESS_KEY" | base64)

    echo "WSS endpoint: $wss_endpoint"
    echo "Session ID:   $session_id"

    # --- Backup the real usbmuxd socket ---
    if [[ -e "$USBMUXD_SOCKET" ]]; then
        echo "Moving $USBMUXD_SOCKET -> $USBMUXD_SOCKET_BACKUP"
        mv "$USBMUXD_SOCKET" "$USBMUXD_SOCKET_BACKUP"
    else
        echo "Warning: $USBMUXD_SOCKET does not exist (no local usbmuxd running?)"
    fi

    # --- Create wrapper for socat EXEC ---
    WRAPPER=$(mktemp /tmp/usbmuxd-ws-XXXXXX)
    printf '#!/bin/bash\nexec websocat --binary "%s" -H "sessionId: %s" -H "Authorization: Basic %s"\n' \
        "$wss_endpoint" "$session_id" "$auth_b64" > "$WRAPPER"
    chmod +x "$WRAPPER"

    # --- Start a persistent keepalive WebSocket with auto-reconnect ---
    # The server sends pings every 10s; websocat auto-responds with pongs, which
    # triggers deviceBinding.touch() on the server to keep the session alive.
    # Without this, the binding expires during idle periods between local connections.
    # The loop auto-reconnects if the server-side bridge closes the idle connection.
    # We pipe from 'tail -f /dev/null' to keep stdin open — /dev/null alone causes immediate EOF.
    echo "Starting keepalive WebSocket..."
    (while true; do
        tail -f /dev/null | websocat --binary "$wss_endpoint" \
            -H "sessionId: $session_id" -H "Authorization: Basic $auth_b64" \
            > /dev/null 2>>"$KEEPALIVE_LOG" || true
        echo "  [keepalive] disconnected, reconnecting in 5s..."
        sleep 5
    done) &
    keepalive_pid=$!
    sleep 2

    if ! kill -0 "$keepalive_pid" 2>/dev/null; then
        echo "Error: keepalive WebSocket failed to connect"
        echo "--- websocat stderr ---"
        cat "$KEEPALIVE_LOG"
        echo "--- end ---"
        quit 1
    fi
    echo "Keepalive WebSocket connected (PID: $keepalive_pid)"

    # --- Start the usbmuxd bridge ---
    echo "Bridging $USBMUXD_SOCKET <-> $wss_endpoint"
    socat UNIX-LISTEN:"${USBMUXD_SOCKET}",fork,unlink-early,mode=0666 \
        EXEC:"$WRAPPER" &
    socat_pid=$!

    # --- Wait for the device to appear ---
    echo "Waiting for device..."
    local retries=0
    local device_udid=""
    while [[ $retries -lt 30 ]]; do
        device_udid=$(idevice_id -l 2>/dev/null | head -1)
        if [[ -n "$device_udid" ]]; then
            break
        fi
        sleep 1
        retries=$((retries + 1))
    done

    if [[ -z "$device_udid" ]]; then
        echo "Error: No device appeared after 30s"
        quit 1
    fi
    echo "Device found: $device_udid"

    # --- Start iproxy for WDA ---
    iproxy "$WDA_PORT" 8100 &
    iproxy_pid=$!
    sleep 1
    echo "WDA proxy started on localhost:$WDA_PORT (via iproxy)"

    cat <<EOF

Device is available in Xcode, Instruments, and other local tools.
WDA is accessible at http://localhost:$WDA_PORT

Example Appium capabilities:
{
  "platformName": "iOS",
  "appium:automationName": "XCUITest",
  "appium:noReset": true,
  "appium:skipDeviceInitialization": true,
  "appium:udid": "$device_udid",
  "appium:webDriverAgentUrl": "http://localhost:$WDA_PORT"
}
EOF
}

handle_ios_caddy() {
    check_dependency 'docker'

    local session_id=$1
    local auth=$(echo -n "$SAUCE_USERNAME:$SAUCE_ACCESS_KEY" | base64)

    echo "SESSION ID: $session_id"

    cat <<EOF > Caddyfile
http://127.0.0.1:$WDA_PORT, http://localhost:$WDA_PORT {
    log {
        output stdout
        format json
    }

    reverse_proxy $SAUCE_API_URL {
            header_up Authorization "Basic $auth"
            transport http {
                tls_insecure_skip_verify
            }
    }

    rewrite * /rdc/v2/sessions/$session_id/device/proxy/http/localhost/8100{uri}
}
EOF

    CADDY_CONTAINER_ID=$(docker run --rm -d -p "$WDA_PORT:$WDA_PORT" \
        -v "$PWD/Caddyfile":/etc/caddy/Caddyfile caddy)
    echo "Caddy container started with ID: $CADDY_CONTAINER_ID"

    cat <<EOF
Example capabilities:
{
  "platformName": "iOS",
  "appium:automationName": "XCUITest",
  "appium:noReset": true,
  "appium:skipDeviceInitialization": true,
  "appium:udid": "auto",
  "appium:webDriverAgentUrl": "http://localhost:$WDA_PORT"
}
EOF
}


# --- Main Script Execution ---

SESSION="$1"

check_dependency 'curl'
check_dependency 'jq'

if [ -z "$SAUCE_USERNAME" ] || [ -z "$SAUCE_ACCESS_KEY" ] || [ -z "$SAUCE_API_URL" ]; then
    echo "Please set SAUCE_API_URL, SAUCE_USERNAME and SAUCE_ACCESS_KEY environment variables"
    quit 1
fi

if [ -z "$SESSION" ]; then
    echo "Usage: $0 <sessionId>"
    quit 1
fi

RESPONSE=""

call_api "$SAUCE_API_URL/rdc/v2/sessions/$SESSION"
STATE=$(echo "$RESPONSE" | jq -r '.state')

while [ "$STATE" == "PENDING" ]; do
    echo "Session creation still pending"
    call_api "$SAUCE_API_URL/rdc/v2/sessions/$SESSION"
    STATE=$(echo "$RESPONSE" | jq -r '.state')
    sleep 5
done

if [ "$STATE" != "ACTIVE" ]; then
    echo "Session not active: $STATE"
    quit 1
fi

os=$(echo "$RESPONSE" | jq -r '.device.os')
session_id=$(echo "$RESPONSE" | jq -r '.id')
wss_endpoint=$(echo "$RESPONSE" | jq -r '.links.vusbUrl')

if [ -z "$wss_endpoint" ] || [ "$wss_endpoint" == "null" ]; then
    echo "Error: No vusbUrl in session response. The session may not have been created with VUSB/live-testing capabilities."
    echo "Available links: $(echo "$RESPONSE" | jq -c '.links')"
    quit 1
fi

if [ "$os" == "ANDROID" ]; then
    echo "Platform: ANDROID"
    handle_android "$wss_endpoint" "$session_id"
else
    echo "Platform: IOS"
    # Rewrite /forward to /usbmuxd for the iOS usbmuxd bridge
    wss_endpoint="${wss_endpoint/\/forward//usbmuxd}"
    handle_ios "$wss_endpoint" "$session_id"
fi

# --- Wait for termination ---
echo
echo "Setup complete. Press Ctrl+C to stop and clean up."
echo

if [ "$os" == "ANDROID" ]; then
    wait "$websocat_pid"
elif [[ -n "$socat_pid" ]]; then
    wait "$socat_pid"
elif [[ -n "$CADDY_CONTAINER_ID" ]]; then
    docker wait "$CADDY_CONTAINER_ID" >/dev/null 2>&1 || true
fi

echo "Background task finished unexpectedly."
quit 0
