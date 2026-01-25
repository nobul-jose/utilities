#!/bin/bash
#
# Reload multipath device table without unmounting
# Fixes "blk_cloned_rq_check_limits" errors by reloading the device mapper table
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

print_info "Reloading multipath device: $DEVICE (without unmounting)"
print_info ""

# Step 1: Verify all values are set correctly
print_info "Step 1: Verifying max_segment_kb values..."

if [ ! -e "/sys/block/$DEVICE" ]; then
    print_error "Device /sys/block/$DEVICE does not exist!"
    exit 1
fi

# Get multipath name
MPATH_NAME=$(dmsetup info -c --noheadings -o name /dev/$DEVICE 2>/dev/null | head -1)
if [ -z "$MPATH_NAME" ]; then
    print_error "Could not determine multipath name for $DEVICE"
    exit 1
fi

print_info "Multipath name: $MPATH_NAME"

# Check current values
CURRENT_MP=$(cat /sys/block/$DEVICE/queue/max_segment_kb 2>/dev/null || echo "unknown")
print_info "Multipath device ($DEVICE): $CURRENT_MP KB"

SLAVES=$(ls /sys/block/$DEVICE/slaves/ 2>/dev/null || echo "")
if [ -z "$SLAVES" ]; then
    print_error "Could not find slave devices"
    exit 1
fi

print_info "Checking underlying paths..."
ALL_SET=true
MIN_PATH_SIZE=999999
for slave in $SLAVES; do
    if [ -e "/sys/block/$slave/queue/max_segment_kb" ]; then
        SIZE=$(cat /sys/block/$slave/queue/max_segment_kb)
        if [ "$SIZE" -lt "$MIN_PATH_SIZE" ]; then
            MIN_PATH_SIZE=$SIZE
        fi
        if [ "$SIZE" -ne 1024 ]; then
            print_warn "  Path $slave: $SIZE KB (should be 1024)"
            ALL_SET=false
        else
            print_info "  ✓ Path $slave: $SIZE KB"
        fi
    fi
done

if [ "$ALL_SET" = false ]; then
    print_warn "Some paths are not set to 1024 KB. Setting them now..."
    for slave in $SLAVES; do
        if [ -e "/sys/block/$slave/queue/max_segment_kb" ]; then
            echo 1024 > /sys/block/$slave/queue/max_segment_kb 2>/dev/null || print_warn "  Could not set $slave"
        fi
    done
    sleep 1
fi

# Ensure multipath device is also 1024
if [ "$CURRENT_MP" != "1024" ]; then
    print_info "Setting multipath device to 1024 KB..."
    echo 1024 > /sys/block/$DEVICE/queue/max_segment_kb 2>/dev/null || print_warn "  Could not set via sysfs (will reload instead)"
fi

# Step 2: Get the current device mapper table
print_info ""
print_info "Step 2: Getting current device mapper table..."

TABLE=$(dmsetup table "$MPATH_NAME" 2>/dev/null)
if [ -z "$TABLE" ]; then
    print_error "Could not get device mapper table for $MPATH_NAME"
    exit 1
fi

print_info "Current table: $TABLE"

# Step 3: Suspend the device (this pauses I/O but doesn't unmount)
print_info ""
print_info "Step 3: Suspending device mapper table (pauses I/O temporarily)..."

if ! dmsetup suspend "$MPATH_NAME" 2>/dev/null; then
    print_error "Failed to suspend device. It may be in use by a critical process."
    print_info "Trying alternative method: reload via multipathd..."
    
    # Alternative: use multipathd to reload
    if command -v multipathd >/dev/null 2>&1; then
        print_info "Using multipathd to reload device..."
        multipathd -k"reconfigure map $MPATH_NAME" 2>/dev/null || {
            print_error "multipathd reload failed"
            exit 1
        }
        print_info "Device reloaded via multipathd"
        sleep 2
    else
        exit 1
    fi
else
    print_info "Device suspended successfully"
    
    # Step 4: Reload the table (this causes it to re-read queue limits)
    print_info "Step 4: Reloading device mapper table..."
    
    # Use dmsetup reload to update the table without changing it
    # This forces the kernel to re-read the underlying device properties
    if dmsetup reload "$MPATH_NAME" --table "$TABLE" 2>/dev/null; then
        print_info "Table reloaded successfully"
    else
        print_warn "dmsetup reload failed, trying resume anyway..."
    fi
    
    # Step 5: Resume the device
    print_info "Step 5: Resuming device..."
    if dmsetup resume "$MPATH_NAME" 2>/dev/null; then
        print_info "Device resumed successfully"
    else
        print_error "Failed to resume device!"
        exit 1
    fi
    
    sleep 2
fi

# Step 6: Verify the fix
print_info ""
print_info "Step 6: Verifying configuration..."

FINAL_MP=$(cat /sys/block/$DEVICE/queue/max_segment_kb 2>/dev/null || echo "unknown")
print_info "Multipath device ($DEVICE): $FINAL_MP KB"

# Check if errors have stopped
print_info ""
print_info "Checking for recent errors in kernel log..."
RECENT_ERRORS=$(dmesg | tail -50 | grep -c "blk_cloned_rq_check_limits" || echo "0")
if [ "$RECENT_ERRORS" -gt 0 ]; then
    print_warn "Still seeing errors in recent kernel log"
    print_info "Recent errors:"
    dmesg | tail -20 | grep "blk_cloned_rq_check_limits" | tail -5 || true
else
    print_info "No recent errors found"
fi

# Step 7: Reload multipath configuration (safe, doesn't require unmount)
print_info ""
print_info "Step 7: Reloading multipath configuration..."

if command -v multipath >/dev/null 2>&1; then
    if multipath -r 2>/dev/null; then
        print_info "Multipath configuration reloaded"
    else
        print_warn "multipath -r had issues (may be normal)"
    fi
fi

# Alternative: use multipathd
if command -v multipathd >/dev/null 2>&1; then
    print_info "Triggering multipathd reconfigure..."
    multipathd -k"reconfigure" 2>/dev/null || true
    sleep 2
fi

print_info ""
print_info "=== Recovery Complete ==="
print_info "Device $DEVICE ($MPATH_NAME) has been reloaded"
print_info ""
print_info "Monitor for errors:"
print_info "  dmesg | tail -f | grep blk_cloned_rq_check_limits"
print_info ""
print_info "If errors persist, you may need to:"
print_info "  1. Wait a few minutes for the recovery loop to settle"
print_info "  2. Check that all paths are actually set to 1024 KB"
print_info "  3. Consider a brief I/O pause if possible"





