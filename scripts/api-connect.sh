#!/bin/bash
set -e

# --- Configuration ---
ADB_PORT=50371
WDA_PORT=8100

# --- Global variables for cleanup ---
# These will hold the process/container IDs for the cleanup function
websocat_pid=""
CADDY_CONTAINER_ID=""
# This variable needs to be accessible by the cleanup function
os=""
# Initialize RESPONSE_FILE early so the quit function can always access it
RESPONSE_FILE=$(mktemp)

# --- Cleanup Functions ---
# This function is the single point of exit. It handles cleaning up
# all resources (Docker containers, processes, temp files).
quit() {
    local exit_code=${1:-0}
    echo # Newline for cleaner exit logs
    echo "Exiting and cleaning up resources..."

    # --- Android Cleanup ---
    # Check if the websocat PID exists and the process is running, then kill it.
    if [[ -n "$websocat_pid" && -e /proc/$websocat_pid ]]; then
        echo "Stopping websocat process (PID: $websocat_pid)..."
        kill "$websocat_pid" 2>/dev/null || true
        echo "Websocat process stopped."
    fi

    # --- iOS Cleanup ---
    # Check if the Caddy container ID exists and the container is running, then stop it.
    # The '--rm' flag used during 'docker run' will ensure the container is removed after stopping.
    if [[ -n "$CADDY_CONTAINER_ID" && $(docker ps -q -f "id=${CADDY_CONTAINER_ID}") ]]; then
        echo "Stopping Caddy container ($CADDY_CONTAINER_ID)..."
        docker stop "$CADDY_CONTAINER_ID" > /dev/null
        echo "Caddy container stopped."
    fi

    # --- General Cleanup ---
    rm -f "$RESPONSE_FILE"

    # Unset the trap to prevent recursive calls on exit
    trap - SIGINT SIGTERM
    exit "$exit_code"
}

# This function is the handler that gets called when a signal is received.
# It simply calls the main 'quit' function to perform the cleanup.
handle_exit_signal() {
    echo # Newline for cleaner logs
    echo "Signal received."
    quit 0
}

# --- Signal Trapping ---
# Trap SIGINT (Ctrl+C) and SIGTERM, and call the cleanup function when they are received.
trap handle_exit_signal SIGINT SIGTERM


# --- Helper Functions ---
check_dependency() {
    if [ -z "$2" ]; then
            PACKAGE="$1"
        else
            PACKAGE="$2"
    fi


    if ! command -v $1 &> /dev/null
    then 
    printf "%s\n\n" "$PACKAGE not installed in the system, please install before using $0"
    fi
}


call_api() {
    local URL=$1
    local METHOD=$2

    if [ -z "$METHOD" ]; then
        METHOD="GET"
    fi

    HTTP_CODE=$(curl -s -X "$METHOD" -u "$SAUCE_USERNAME:$SAUCE_ACCESS_KEY" -o "$RESPONSE_FILE" -w "%{http_code}" "$URL")

    if [ "$HTTP_CODE" -ne 200 ]; then
        echo "Error HTTP $HTTP_CODE"
        cat "$RESPONSE_FILE"|jq .
        rm "$RESPONSE_FILE"
        quit 1
    fi

    RESPONSE=$(cat $RESPONSE_FILE)
}


# --- OS-Specific Handlers ---
handle_android() {
    check_dependency 'websocat'
    check_dependency 'adb'

    local wss_endpoint=$1
    local session_id=$2

    websocat -b tcp-l:127.0.0.1:$ADB_PORT $wss_endpoint -E -H "sessionId: $session_id" --basic-auth "$SAUCE_USERNAME:$SAUCE_ACCESS_KEY" &

    websocat_pid=$!
    sleep 1
    
    echo "websocat started with PID: $websocat_pid on port $ADB_PORT"

    adb connect localhost:$ADB_PORT
    echo "ADB connected! You can start your appium server with 'appium --allow-insecure chromedriver_autodownload'"

    # Display example capabilities for the user
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

    # Run the caddy container in detached mode (-d) and store the container ID
    # in the global variable. The '--rm' flag ensures it's removed on stop.
    CADDY_CONTAINER_ID=$(docker run --rm -d -p "$WDA_PORT:$WDA_PORT" -v "$PWD/Caddyfile":/etc/caddy/Caddyfile caddy)
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

quit() {
    local exit_code=${1:-0}
    echo # Newline for cleaner exit logs
    echo "Exiting and cleaning up resources..."

    # --- Android Cleanup ---
    # Check if the websocat PID exists and the process is running, then kill it.
    if [[ -n "$websocat_pid" ]] && kill -0 "$websocat_pid" 2>/dev/null; then
        echo "Stopping websocat process (PID: $websocat_pid)..."
        kill "$websocat_pid" 2>/dev/null || true
        adb disconnect localhost:$ADB_PORT
        echo "Websocat process stopped."
    fi

    # --- iOS Cleanup ---
    # Check if the Caddy container ID exists and the container is running, then stop it.
    # The '--rm' flag used during 'docker run' will ensure the container is removed after stopping.
    if [[ -n "$CADDY_CONTAINER_ID" && $(docker ps -q -f "id=${CADDY_CONTAINER_ID}") ]]; then
        echo "Stopping Caddy container ($CADDY_CONTAINER_ID)..."
        docker stop "$CADDY_CONTAINER_ID" > /dev/null
        echo "Caddy container stopped."
    fi

    # --- General Cleanup ---
    rm -f "$RESPONSE_FILE"

    # Unset the trap to prevent recursive calls on exit
    trap - SIGINT SIGTERM
    exit "$exit_code"
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
    echo "Usage $0 <sessionId>"
fi

RESPONSE=""

call_api "$SAUCE_API_URL/rdc/v2/sessions/$SESSION"
STATE=$(echo $RESPONSE|jq -r '.state')

while [ "$STATE" == "PENDING" ]; do
    echo "Session creation still pending"
    call_api "$SAUCE_API_URL/rdc/v2/sessions/$SESSION"
    STATE=$(echo $RESPONSE|jq -r '.state')
    sleep 5
done

if [ "$STATE" != "ACTIVE" ]; then
    echo "Session not active: $STATE"
    quit 1
fi

os=$(echo $RESPONSE|jq -r '.device.os')

if [ "$os" == "ANDROID" ]; then
    echo "Platform: ANDROID"
    wss_endpoint=$(echo $RESPONSE|jq -r '.links.vusbUrl') 
    session_id=$(echo $RESPONSE|jq -r '.id') 
    handle_android $wss_endpoint $session_id
else
    echo "Platform: IOS"
    session_id=$(echo $RESPONSE|jq -r '.id') 
    handle_ios $session_id
fi

# --- Wait for termination ---
# The script will now pause here. The 'trap' command set earlier will
# catch Ctrl+C or SIGTERM, run the 'quit' function for cleanup, and exit.
# If the background task exits on its own, the 'wait' or 'docker wait'
# command will also complete, and the script will then call 'quit'.
echo
echo "Setup complete. The script is now running and waiting for a signal."
echo "Press Ctrl+C or send a SIGTERM to stop and clean up."
echo

if [ "$os" == "ANDROID" ]; then
    # Wait for the websocat process to exit. This will be interrupted by the trap.
    wait "$websocat_pid"
else
    # 'docker wait' will block until the container stops. This will be interrupted
    # when the trap calls 'docker stop'.
    docker wait "$CADDY_CONTAINER_ID" >/dev/null 2>&1 || true
fi

# If we reach this point, it means the background task ended on its own.
# We call quit to ensure consistent cleanup and exit.
echo "Background task finished unexpectedly."
quit 0