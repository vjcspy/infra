#!/bin/bash
set -e

K3S_STATE_EBS="/mnt/existing_ebs_volume/k3s-state"
K3S_STATE_LOCAL="/var/lib/rancher/k3s"

if [ ! -f "/mnt/existing_ebs_volume/DONT_DELETE" ]; then
    echo "ERROR: EBS volume not mounted at /mnt/existing_ebs_volume"
    exit 1
fi

# K3S state must come from EBS; never start K3S on the root volume
if [ ! -d "$K3S_STATE_EBS/server" ]; then
    echo "ERROR: K3S state not found at $K3S_STATE_EBS/server; refusing to start K3S on the root volume." \
         "Restore the app volume from a snapshot, or create $K3S_STATE_EBS/server to bootstrap a new cluster on purpose."
    exit 1
fi

if mountpoint -q "$K3S_STATE_LOCAL" 2>/dev/null; then
    echo "K3S state already bind-mounted at $K3S_STATE_LOCAL"
    exit 0
fi

mkdir -p "$K3S_STATE_LOCAL"
mount --bind "$K3S_STATE_EBS" "$K3S_STATE_LOCAL"
echo "K3S state bind mount OK: $K3S_STATE_EBS → $K3S_STATE_LOCAL"
