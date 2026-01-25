#!/bin/bash
#
# Recovery script for multipath device max_segment_kb issues
# Fixes "blk_cloned_rq_check_limits: over max size limit" errors
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

DEVICE="${1:-dm-4}"

print_info "Recovering multipath device: $DEVICE"
print_info ""

# Step 1: Find the underlying paths for this multipath device
print_info "Step 1: Finding underlying paths for $DEVICE..."

if [ ! -e "/sys/block/$DEVICE" ]; then
    print_error "Device /sys/block/$DEVICE does not exist!"
    exit 1
fi

# Get underlying paths from multipath
print_info "Checking multipath status..."
if command -v multipath >/dev/null 2>&1; then
    multipath -ll | grep -A 20 "$DEVICE" || true
fi

# Find slave devices
SLAVES=$(ls /sys/block/$DEVICE/slaves/ 2>/dev/null || echo "")
if [ -z "$SLAVES" ]; then
    print_warn "No slaves found in /sys/block/$DEVICE/slaves/"
    print_info "Trying to find paths via dm..."
    SLAVES=$(dmsetup deps /dev/$DEVICE 2>/dev/null | sed 's/.*: //' | tr ' ' '\n' | grep -v '^$' || echo "")
fi

if [ -z "$SLAVES" ]; then
    print_error "Could not determine underlying paths. Please check manually."
    exit 1
fi

print_info "Found underlying paths: $SLAVES"

# Step 2: Check current max_segment_kb values
print_info ""
print_info "Step 2: Checking current max_segment_kb values..."

CURRENT_MP=$(cat /sys/block/$DEVICE/queue/max_segment_kb 2>/dev/null || echo "unknown")
print_info "Multipath device ($DEVICE): $CURRENT_MP KB"

MIN_PATH_SIZE=999999
for slave in $SLAVES; do
    if [ -e "/sys/block/$slave/queue/max_segment_kb" ]; then
        SIZE=$(cat /sys/block/$slave/queue/max_segment_kb)
        print_info "  Path $slave: $SIZE KB"
        if [ "$SIZE" -lt "$MIN_PATH_SIZE" ]; then
            MIN_PATH_SIZE=$SIZE
        fi
    else
        print_warn "  Path $slave: not found or not accessible"
    fi
done

if [ "$MIN_PATH_SIZE" -eq 999999 ]; then
    print_error "Could not determine minimum path size"
    exit 1
fi

print_info ""
print_info "Minimum path size: $MIN_PATH_SIZE KB"
print_info "Multipath device must be <= $MIN_PATH_SIZE KB"

# Step 3: Set all paths to a safe value (1024 is common default)
print_info ""
print_info "Step 3: Setting all underlying paths to 1024 KB..."

TARGET_SIZE=1024
for slave in $SLAVES; do
    if [ -e "/sys/block/$slave/queue/max_segment_kb" ]; then
        print_info "  Setting $slave to $TARGET_SIZE KB..."
        echo "$TARGET_SIZE" > /sys/block/$slave/queue/max_segment_kb 2>/dev/null || {
            print_warn "  Failed to set $slave (may be read-only or in use)"
        }
        # Verify
        ACTUAL=$(cat /sys/block/$slave/queue/max_segment_kb)
        if [ "$ACTUAL" -eq "$TARGET_SIZE" ]; then
            print_info "    ✓ Verified: $slave = $ACTUAL KB"
        else
            print_warn "    ⚠ Warning: $slave = $ACTUAL KB (expected $TARGET_SIZE)"
        fi
    fi
done

# Step 4: Set multipath device to match or be less than minimum
print_info ""
print_info "Step 4: Setting multipath device to $TARGET_SIZE KB..."

# First, try to flush any pending I/O
print_info "  Attempting to flush I/O..."
blockdev --flushbufs /dev/$DEVICE 2>/dev/null || print_warn "  Could not flush buffers (may be normal)"

# Set the multipath device
if [ -w "/sys/block/$DEVICE/queue/max_segment_kb" ]; then
    echo "$TARGET_SIZE" > /sys/block/$DEVICE/queue/max_segment_kb 2>/dev/null || {
        print_error "Failed to set multipath device max_segment_kb"
        print_info "You may need to:"
        print_info "  1. Stop I/O to this device"
        print_info "  2. Unmount filesystems using it"
        print_info "  3. Reload the multipath device"
        exit 1
    }
    
    # Verify
    ACTUAL=$(cat /sys/block/$DEVICE/queue/max_segment_kb)
    if [ "$ACTUAL" -eq "$TARGET_SIZE" ]; then
        print_info "    ✓ Verified: $DEVICE = $ACTUAL KB"
    else
        print_warn "    ⚠ Warning: $DEVICE = $ACTUAL KB (expected $TARGET_SIZE)"
    fi
else
    print_error "Cannot write to /sys/block/$DEVICE/queue/max_segment_kb"
    print_info "The device may be in use or the sysfs entry is read-only"
    print_info ""
    print_info "Try these steps manually:"
    print_info "  1. Unmount any filesystems using /dev/$DEVICE"
    print_info "  2. Stop any applications using the device"
    print_info "  3. Reload multipath: multipath -r"
    print_info "  4. Then run this script again"
    exit 1
fi

# Step 5: Verify the fix
print_info ""
print_info "Step 5: Verifying configuration..."

FINAL_MP=$(cat /sys/block/$DEVICE/queue/max_segment_kb)
print_info "Final multipath device ($DEVICE): $FINAL_MP KB"

ALL_OK=true
for slave in $SLAVES; do
    if [ -e "/sys/block/$slave/queue/max_segment_kb" ]; then
        SIZE=$(cat /sys/block/$slave/queue/max_segment_kb)
        if [ "$SIZE" -lt "$FINAL_MP" ]; then
            print_error "  ✗ ERROR: Path $slave ($SIZE KB) < Multipath ($FINAL_MP KB)"
            ALL_OK=false
        else
            print_info "  ✓ Path $slave: $SIZE KB (OK)"
        fi
    fi
done

if [ "$ALL_OK" = true ]; then
    print_info ""
    print_info "=== Recovery Complete ==="
    print_info "Multipath device $DEVICE is now configured correctly"
    print_info "The 'blk_cloned_rq_check_limits' errors should stop"
    print_info ""
    print_info "Monitor kernel logs: dmesg | tail -f"
else
    print_error ""
    print_error "=== Configuration Issue ==="
    print_error "Some paths are still smaller than the multipath device"
    print_error "You may need to reload the multipath device"
    exit 1
fi

# Step 6: Optional - reload multipath if needed
print_info ""
read -p "Reload multipath configuration? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Reloading multipath..."
    multipath -r 2>/dev/null || print_warn "multipath -r failed (may be normal)"
    print_info "Multipath reloaded"
fi

print_info ""
print_info "Done!"





