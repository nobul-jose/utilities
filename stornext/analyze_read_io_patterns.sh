#!/bin/bash
#
# StorNext cvdb Read IO Pattern Analysis Script
# This script helps troubleshoot performance by analyzing read IO patterns
# for a parent directory using cvdb and snseq
#

set -e

# Configuration
TRACE_DIR="${TRACE_DIR:-/tmp/cvdb_traces}"
PARENT_DIR="${PARENT_DIR:-}"
DURATION="${DURATION:-60}"  # seconds
OUTPUT_FILE="${OUTPUT_FILE:-read_io_analysis.out}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root (cvdb typically needs root)
if [ "$EUID" -ne 0 ]; then 
    print_warn "This script may need root privileges to run cvdb commands"
fi

# Create trace directory
print_info "Creating trace directory: $TRACE_DIR"
mkdir -p "$TRACE_DIR"
cd "$TRACE_DIR"

# Clean up any existing traces
print_info "Cleaning up any existing trace files..."
rm -f cvdbout.* 2>/dev/null || true

# Function to cleanup on exit
cleanup() {
    print_info "Cleaning up..."
    # Kill cvdb if still running
    pkill -f "cvdb -g" 2>/dev/null || true
    # Disable tracing
    cvdbset -d 2>/dev/null || true
    print_info "Cleanup complete"
}

trap cleanup EXIT INT TERM

# Step 1: Enable performance tracing
print_info "Step 1: Enabling performance tracing with 'perf' module"
if ! cvdbset perf; then
    print_error "Failed to enable perf tracing. Make sure StorNext is properly installed."
    exit 1
fi

# Verify tracing is enabled
print_info "Verifying tracing is enabled..."
cvdbset | head -5

# Step 2: Start capturing traces
print_info "Step 2: Starting continuous trace capture (will run for $DURATION seconds)"
print_info "Trace files will be saved to: $TRACE_DIR/cvdbout.*"
print_info ""
print_warn "Now perform your read operations on: ${PARENT_DIR:-the target directory}"
print_warn "The script will capture traces for $DURATION seconds..."
print_info ""

# Start cvdb in background
cvdb -g -C -F &
CVDB_PID=$!

# Wait for specified duration
sleep "$DURATION"

# Step 3: Stop tracing
print_info "Step 3: Stopping trace capture..."
kill $CVDB_PID 2>/dev/null || true
wait $CVDB_PID 2>/dev/null || true

# Disable tracing
print_info "Disabling tracing..."
cvdbset -d

# Step 4: Analyze read patterns with snseq
print_info "Step 4: Analyzing read IO patterns with snseq..."

if [ ! -f cvdbout.000000 ] && [ -z "$(ls -A cvdbout.* 2>/dev/null)" ]; then
    print_error "No trace files found! Make sure read operations were performed during capture."
    exit 1
fi

# Count trace files
TRACE_COUNT=$(ls -1 cvdbout.* 2>/dev/null | wc -l)
print_info "Found $TRACE_COUNT trace file(s)"

# Analyze reads with details
print_info "Running snseq read analysis..."
if command -v snseq >/dev/null 2>&1; then
    # Basic read analysis
    print_info "=== Basic Read Analysis ===" > "$OUTPUT_FILE"
    snseq read cvdbout.* >> "$OUTPUT_FILE" 2>&1 || print_warn "snseq read failed, trying with --details"
    
    # Detailed read analysis
    print_info "" >> "$OUTPUT_FILE"
    print_info "=== Detailed Read Analysis ===" >> "$OUTPUT_FILE"
    snseq read --details cvdbout.* >> "$OUTPUT_FILE" 2>&1 || print_warn "snseq read --details had issues"
    
    # Per-second analysis
    print_info "" >> "$OUTPUT_FILE"
    print_info "=== Per-Second Read Analysis ===" >> "$OUTPUT_FILE"
    snseq read --persec cvdbout.* >> "$OUTPUT_FILE" 2>&1 || print_warn "snseq read --persec had issues"
    
    print_info "Analysis complete! Results saved to: $TRACE_DIR/$OUTPUT_FILE"
    print_info ""
    print_info "=== Summary of Read IO Patterns ==="
    head -50 "$OUTPUT_FILE"
    
    # If parent directory was specified, try to filter
    if [ -n "$PARENT_DIR" ]; then
        print_info ""
        print_info "Note: To filter results for '$PARENT_DIR', you may need to:"
        print_info "  grep '$PARENT_DIR' $OUTPUT_FILE"
    fi
else
    print_error "snseq command not found!"
    print_info "Trace files are available in: $TRACE_DIR"
    print_info "You can analyze them manually with: snseq read --details $TRACE_DIR/cvdbout.*"
    exit 1
fi

print_info ""
print_info "=== Analysis Complete ==="
print_info "Full results: $TRACE_DIR/$OUTPUT_FILE"
print_info "Trace files: $TRACE_DIR/cvdbout.*"
print_info ""
print_info "Key things to look for in the output:"
print_info "  - Sequential vs random read patterns"
print_info "  - I/O sizes and throughput"
print_info "  - Latency (mics = microseconds)"
print_info "  - File fragmentation (exts = extent count)"
print_info "  - VFS vs Device level performance"





