#!/bin/sh

# Chạy dvt-splunk_licsrv với port 3001
/app/dvt-splunk_licsrv.1.0.linux.amd64 -port 3001 &

(
    chmod +x /app/splunk/bin/splunk &&
    cd /app/splunk/bin || exit 1
    ./splunk start --accept-license
) && tail -f /dev/null