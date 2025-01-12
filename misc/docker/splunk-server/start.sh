#!/bin/sh

# Trap SIGTERM and SIGINT
trap 'cleanup' TERM INT

cleanup() {
    echo "Stopping processes..."
    [ -n "$LICENSE_SERVER_PID" ] && kill $LICENSE_SERVER_PID
    cd /app/splunk/bin && ./splunk stop
    exit 0
}

# Start Splunk
(
    chmod +x /app/splunk/bin/splunk &&
    cd /app/splunk/bin || exit 1
    ./splunk start --accept-license
) && tail -f /dev/null