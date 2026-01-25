#!/bin/bash
#
# Quick reload of multipath device to fix blk_cloned_rq_check_limits errors
# Minimal version - just reloads the device table
#

set -e

if [ "$EUID" -ne 0 ]; then 
    echo "Must run as root"
    exit 1
fi

DEVICE="${1:-dm-4}"

echo "Reloading multipath device: $DEVICE"

# Get multipath name
MPATH_NAME=$(dmsetup info -c --noheadings -o name /dev/$DEVICE 2>/dev/null | head -1)
if [ -z "$MPATH_NAME" ]; then
    echo "Error: Could not determine multipath name"
    exit 1
fi

echo "Multipath name: $MPATH_NAME"

# Method 1: Suspend, reload, resume
echo "Suspending device..."
if dmsetup suspend "$MPATH_NAME" 2>/dev/null; then
    echo "Reloading table..."
    TABLE=$(dmsetup table "$MPATH_NAME")
    dmsetup reload "$MPATH_NAME" --table "$TABLE" 2>/dev/null || true
    echo "Resuming device..."
    dmsetup resume "$MPATH_NAME" 2>/dev/null || {
        echo "ERROR: Failed to resume device!"
        exit 1
    }
    echo "Device reloaded successfully"
else
    echo "Suspend failed, trying multipathd method..."
    # Method 2: Use multipathd
    if command -v multipathd >/dev/null 2>&1; then
        multipathd -k"reconfigure map $MPATH_NAME" 2>/dev/null && echo "Reloaded via multipathd" || echo "multipathd reload failed"
    fi
fi

# Also reload multipath config
multipath -r 2>/dev/null || true

echo "Done. Monitor with: dmesg | tail -f"





