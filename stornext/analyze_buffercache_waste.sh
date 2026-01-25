#!/bin/bash
#
# StorNext Buffer Cache Waste Analysis Script
# This script analyzes cvdb traces to detect wasted buffer cache reads
# caused by excessive cachebuffersize mount settings
#
# It identifies buffer reads that were never consumed by applications,
# helping to optimize cachebuffersize settings
#

set -e

# Configuration
TRACE_DIR="${TRACE_DIR:-/tmp/cvdb_buffer_analysis}"
DURATION="${DURATION:-60}"  # seconds
OUTPUT_FILE="${OUTPUT_FILE:-buffercache_waste_analysis.out}"
ANALYSIS_DIR="${ANALYSIS_DIR:-$TRACE_DIR/analysis}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

print_section() {
    echo -e "\n${CYAN}=== $1 ===${NC}"
}

# Check if running as root (cvdb typically needs root)
if [ "$EUID" -ne 0 ]; then 
    print_warn "This script may need root privileges to run cvdb commands"
fi

# Create trace and analysis directories
print_info "Creating directories: $TRACE_DIR and $ANALYSIS_DIR"
mkdir -p "$TRACE_DIR"
mkdir -p "$ANALYSIS_DIR"
cd "$TRACE_DIR"

# Clean up any existing traces
print_info "Cleaning up any existing trace files..."
rm -f cvdbout.* 2>/dev/null || true
rm -f "$ANALYSIS_DIR"/* 2>/dev/null || true

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

# Step 1: Enable performance and buffer tracing
print_section "Step 1: Enabling Performance and Buffer Tracing"
print_info "Enabling 'perf' and 'rwbuf' modules for buffer cache analysis"
if ! cvdbset perf rwbuf vnops; then
    print_error "Failed to enable tracing modules. Make sure StorNext is properly installed."
    exit 1
fi

# Verify tracing is enabled
print_info "Verifying tracing is enabled..."
cvdbset | head -10

# Step 2: Start capturing traces
print_section "Step 2: Starting Trace Capture"
print_info "Trace capture will run for $DURATION seconds"
print_info "Trace files will be saved to: $TRACE_DIR/cvdbout.*"
print_info ""
print_warn "Now perform your read operations that you want to analyze"
print_warn "The script will capture buffer cache activity for $DURATION seconds..."
print_info ""

# Start cvdb in background
W &
CVDB_PID=$!

# Wait for specified duration
sleep "$DURATION"

# Step 3: Stop tracing
print_section "Step 3: Stopping Trace Capture"
print_info "Stopping trace capture..."
kill $CVDB_PID 2>/dev/null || true
wait $CVDB_PID 2>/dev/null || true

# Disable tracing
print_info "Disabling tracing..."
cvdbset -d

# Step 4: Analyze traces for buffer cache waste
print_section "Step 4: Analyzing Buffer Cache Waste"

if [ ! -f cvdbout.000000 ] && [ -z "$(ls -A cvdbout.* 2>/dev/null)" ]; then
    print_error "No trace files found! Make sure read operations were performed during capture."
    exit 1
fi

# Count trace files
TRACE_COUNT=$(ls -1 cvdbout.* 2>/dev/null | wc -l)
print_info "Found $TRACE_COUNT trace file(s)"

# Create Python analysis script
cat > "$ANALYSIS_DIR/analyze_buffer_waste.py" << 'PYTHON_EOF'
#!/usr/bin/env python3
"""
Analyze cvdb traces to detect buffer cache waste.

This script analyzes the relationship between:
1. Device-level reads (what gets read into buffer cache)
2. VFS-level reads (what applications actually request)
3. Buffer cache operations (rwbuf traces)

High overfetch ratios indicate cachebuffersize may be too large.
"""

import re
import sys
import glob
from collections import defaultdict

def parse_perf_line(line):
    """Parse a PERF trace line from cvdb."""
    # Examples:
    # PERF: Device Read 150 MB/s IOs 3 exts 2 offs 0x100000 len 0x200000 mics 13333 ino 0x1234
    # PERF: VFS Read Buf 150 MB/s offs 0x100000 len 0x200000 mics 13500 ino 0x1234
    
    result = {
        'type': None,
        'ino': None,
        'offset': None,
        'length': None,
        'flags': [],
        'line': line.strip()
    }
    
    line_lower = line.lower()
    
    # Determine type
    if 'perf: device read' in line_lower:
        result['type'] = 'device_read'
    elif 'perf: vfs read' in line_lower:
        result['type'] = 'vfs_read'
    else:
        return None
    
    # Extract inode number
    ino_match = re.search(r'ino\s+0x([0-9a-fA-F]+)', line, re.I)
    if ino_match:
        result['ino'] = int(ino_match.group(1), 16)
    else:
        return None  # Need inode to correlate
    
    # Extract offset
    offs_match = re.search(r'offs\s+0x([0-9a-fA-F]+)', line, re.I)
    if offs_match:
        result['offset'] = int(offs_match.group(1), 16)
    else:
        return None
    
    # Extract length
    len_match = re.search(r'len\s+0x([0-9a-fA-F]+)', line, re.I)
    if len_match:
        result['length'] = int(len_match.group(1), 16)
    else:
        return None
    
    # Extract flags (Buf, Dma, Algn, etc.)
    if 'buf' in line_lower:
        result['flags'].append('Buf')
    if 'dma' in line_lower:
        result['flags'].append('Dma')
    if 'algn' in line_lower:
        result['flags'].append('Algn')
    
    return result

def parse_rwbuf_line(line):
    """Parse RWBUF trace lines."""
    # RWBUF entries show buffer cache operations
    line_lower = line.lower()
    if 'rwbuf' in line_lower:
        return {'type': 'rwbuf', 'line': line.strip()}
    return None

def analyze_buffer_waste(trace_files):
    """Analyze trace files to detect buffer cache waste."""
    
    device_reads = []  # All device-level reads (buffer cache fills)
    vfs_reads = []     # VFS reads (application requests)
    rwbuf_entries = [] # Buffer cache operations
    
    print("Parsing trace files...")
    total_lines = 0
    
    for trace_file in sorted(trace_files):
        try:
            with open(trace_file, 'r', errors='ignore') as f:
                for line in f:
                    total_lines += 1
                    
                    # Parse PERF entries
                    perf_entry = parse_perf_line(line)
                    if perf_entry:
                        if perf_entry['type'] == 'device_read':
                            device_reads.append(perf_entry)
                        elif perf_entry['type'] == 'vfs_read':
                            vfs_reads.append(perf_entry)
                        continue
                    
                    # Parse RWBUF entries
                    rwbuf_entry = parse_rwbuf_line(line)
                    if rwbuf_entry:
                        rwbuf_entries.append(rwbuf_entry)
        except Exception as e:
            print(f"Warning: Error reading {trace_file}: {e}", file=sys.stderr)
            continue
    
    print(f"Processed {total_lines:,} lines")
    print(f"Found {len(device_reads):,} device reads, {len(vfs_reads):,} VFS reads, {len(rwbuf_entries):,} RWBUF entries")
    
    # Calculate statistics
    total_device_bytes = sum(d['length'] for d in device_reads)
    total_vfs_bytes = sum(v['length'] for v in vfs_reads)
    
    # Separate buffered vs direct device reads
    buffered_device_reads = [d for d in device_reads if 'Buf' in d['flags']]
    buffered_device_bytes = sum(d['length'] for d in buffered_device_reads)
    
    # Calculate average read sizes
    avg_device_read_size = total_device_bytes / len(device_reads) if device_reads else 0
    avg_vfs_read_size = total_vfs_bytes / len(vfs_reads) if vfs_reads else 0
    avg_buffered_read_size = buffered_device_bytes / len(buffered_device_reads) if buffered_device_reads else 0
    
    # Calculate overfetch ratio (how much more was read than requested)
    overfetch_ratio = ((total_device_bytes - total_vfs_bytes) / total_vfs_bytes * 100) if total_vfs_bytes > 0 else 0
    buffered_overfetch_ratio = ((buffered_device_bytes - total_vfs_bytes) / total_vfs_bytes * 100) if total_vfs_bytes > 0 else 0
    
    # Calculate buffer read vs VFS read ratio
    buffer_to_vfs_ratio = (buffered_device_bytes / total_vfs_bytes) if total_vfs_bytes > 0 else 0
    
    # Output results
    print("\n" + "="*70)
    print("BUFFER CACHE WASTE ANALYSIS RESULTS")
    print("="*70)
    
    print(f"\n📊 READ STATISTICS")
    print(f"{'Metric':<35} {'Count':>12} {'Bytes':>15} {'Avg Size':>12}")
    print("-" * 74)
    print(f"{'Device Reads (all)':<35} {len(device_reads):>12,} {total_device_bytes:>15,} {avg_device_read_size/1024:>11.1f} KB")
    print(f"{'  └─ Buffered Device Reads':<35} {len(buffered_device_reads):>12,} {buffered_device_bytes:>15,} {avg_buffered_read_size/1024:>11.1f} KB")
    print(f"{'VFS Reads (app requests)':<35} {len(vfs_reads):>12,} {total_vfs_bytes:>15,} {avg_vfs_read_size/1024:>11.1f} KB")
    print(f"{'RWBUF Operations':<35} {len(rwbuf_entries):>12,}")
    
    print(f"\n📈 CACHE ANALYSIS")
    print(f"Buffer Cache Size Ratio:     {buffer_to_vfs_ratio:>10.2f}x")
    print(f"  (Buffer reads / VFS reads)")
    print(f"")
    print(f"Total Overfetch Ratio:       {overfetch_ratio:>10.1f}%")
    print(f"  (Extra device reads beyond VFS requests)")
    print(f"")
    print(f"Buffered Overfetch Ratio:    {buffered_overfetch_ratio:>10.1f}%")
    print(f"  (Extra buffered reads beyond VFS requests)")
    
    # Size comparison
    if avg_buffered_read_size > 0 and avg_vfs_read_size > 0:
        size_ratio = avg_buffered_read_size / avg_vfs_read_size
        print(f"")
        print(f"Average Read Size Ratio:     {size_ratio:>10.2f}x")
        print(f"  (Avg buffer read / Avg VFS read)")
    
    # Interpretation
    print("\n" + "="*70)
    print("INTERPRETATION")
    print("="*70)
    
    # Analyze buffer-to-vfs ratio
    if buffer_to_vfs_ratio > 3.0:
        print(f"\n⚠️  VERY HIGH BUFFER OVERFETCH ({buffer_to_vfs_ratio:.2f}x)")
        print("   The buffer cache is reading {:.1f}x more data than applications request.".format(buffer_to_vfs_ratio))
        print("   This strongly suggests cachebuffersize is MUCH too large.")
        print("   Recommendation: Significantly reduce cachebuffersize mount option.")
        print("   Expected ratio should be closer to 1.0-1.5x for most workloads.")
    elif buffer_to_vfs_ratio > 2.0:
        print(f"\n⚠️  HIGH BUFFER OVERFETCH ({buffer_to_vfs_ratio:.2f}x)")
        print("   The buffer cache is reading significantly more data than needed.")
        print("   Your cachebuffersize setting appears too large.")
        print("   Recommendation: Reduce cachebuffersize mount option.")
        print("   Try reducing by 30-50% and re-measure.")
    elif buffer_to_vfs_ratio > 1.5:
        print(f"\n⚠️  MODERATE BUFFER OVERFETCH ({buffer_to_vfs_ratio:.2f}x)")
        print("   The buffer cache is reading more than applications request.")
        print("   Consider reducing cachebuffersize to optimize performance.")
    elif buffer_to_vfs_ratio > 1.1:
        print(f"\n✓  SLIGHT BUFFER OVERFETCH ({buffer_to_vfs_ratio:.2f}x)")
        print("   Some overfetch is normal for read-ahead optimization.")
        print("   Current setting appears reasonable.")
    else:
        print(f"\n✓  MINIMAL OVERFETCH ({buffer_to_vfs_ratio:.2f}x)")
        print("   Buffer cache reads are closely aligned with application requests.")
    
    # Analyze buffered overfetch ratio
    if buffered_overfetch_ratio > 100:
        print(f"\n⚠️  EXTREME WASTE ({buffered_overfetch_ratio:.1f}% extra reads)")
        print("   More than {:.0f}% of buffered reads appear to be wasted.".format(buffered_overfetch_ratio))
        print("   This is causing significant unnecessary I/O and slowing performance.")
    elif buffered_overfetch_ratio > 50:
        print(f"\n⚠️  HIGH WASTE ({buffered_overfetch_ratio:.1f}% extra reads)")
        print("   Significant portion of buffer reads are going to waste.")
    
    # Analyze read size ratio
    if avg_buffered_read_size > 0 and avg_vfs_read_size > 0:
        size_ratio = avg_buffered_read_size / avg_vfs_read_size
        if size_ratio > 4.0:
            print(f"\n⚠️  LARGE READ SIZE MISMATCH ({size_ratio:.2f}x)")
            print("   Buffer cache reads are much larger than application requests.")
            print("   This suggests cachebuffersize exceeds the access pattern.")
            print("   Applications are requesting smaller chunks, but cache is reading large blocks.")
    
    print("\n" + "="*70)
    print("RECOMMENDATIONS")
    print("="*70)
    
    if buffer_to_vfs_ratio > 2.0:
        print("\n1. Reduce cachebuffersize mount option significantly")
        print("2. Re-run this analysis to verify improvement")
        print("3. Monitor actual application performance after changes")
        print("4. Consider reducing cachebuffersize by 50-70% if ratio > 3.0x")
    elif buffer_to_vfs_ratio > 1.5:
        print("\n1. Consider reducing cachebuffersize by 25-40%")
        print("2. Re-run analysis to compare results")
        print("3. Balance between read-ahead benefits and waste")
    else:
        print("\n1. Current cachebuffersize appears reasonable")
        print("2. Monitor for different workload patterns")
        print("3. Fine-tune if needed based on specific use cases")
    
    print("\n" + "="*70)
    
    return {
        'device_reads': len(device_reads),
        'device_bytes': total_device_bytes,
        'buffered_reads': len(buffered_device_reads),
        'buffered_bytes': buffered_device_bytes,
        'vfs_reads': len(vfs_reads),
        'vfs_bytes': total_vfs_bytes,
        'buffer_to_vfs_ratio': buffer_to_vfs_ratio,
        'overfetch_ratio': overfetch_ratio,
        'buffered_overfetch_ratio': buffered_overfetch_ratio
    }

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: analyze_buffer_waste.py <trace_file1> [trace_file2] ...")
        sys.exit(1)
    
    trace_files = sys.argv[1:]
    # Expand globs if needed
    expanded_files = []
    for pattern in trace_files:
        expanded_files.extend(glob.glob(pattern))
    
    if not expanded_files:
        print(f"Error: No trace files found matching: {trace_files}", file=sys.stderr)
        sys.exit(1)
    
    analyze_buffer_waste(expanded_files)

PYTHON_EOF

chmod +x "$ANALYSIS_DIR/analyze_buffer_waste.py"

# Step 5: Run the analysis
print_info "Running buffer cache waste analysis..."
python3 "$ANALYSIS_DIR/analyze_buffer_waste.py" cvdbout.* > "$OUTPUT_FILE" 2>&1

# Also save raw trace analysis and optional snseq analysis
print_info "Saving detailed trace information..."

{
    echo ""
    echo "=== Raw Trace Statistics ==="
    echo ""
    echo "Buffer cache related entries (RWBUF):"
    grep -i "rwbuf" cvdbout.* 2>/dev/null | wc -l || echo "0"
    echo ""
    echo "Buffered I/O entries (Buf flag):"
    grep -i "perf:.*buf" cvdbout.* 2>/dev/null | wc -l || echo "0"
    echo ""
    echo "VFS Read entries (application requests):"
    grep -i "perf: vfs read" cvdbout.* 2>/dev/null | wc -l || echo "0"
    echo ""
    echo "Device Read entries (disk I/O, includes buffer fills):"
    grep -i "perf: device read" cvdbout.* 2>/dev/null | wc -l || echo "0"
    echo ""
    echo "Sample VFS Read entries:"
    grep -i "perf: vfs read" cvdbout.* 2>/dev/null | head -10 || echo "None found"
    echo ""
    echo "Sample Buffered Device Read entries:"
    grep -i "perf: device read.*buf" cvdbout.* 2>/dev/null | head -10 || echo "None found"
    echo ""
    echo "Sample RWBUF entries:"
    grep -i "rwbuf" cvdbout.* 2>/dev/null | head -10 || echo "None found"
} >> "$OUTPUT_FILE"

# If snseq is available, add its analysis
if command -v snseq >/dev/null 2>&1; then
    print_info "Running snseq analysis for additional insights..."
    {
        echo ""
        echo "=== snseq Read Analysis ==="
        echo ""
        snseq read --details cvdbout.* 2>&1 | head -100 || echo "snseq analysis failed"
    } >> "$OUTPUT_FILE"
fi

# Display results
print_section "Analysis Complete"
print_info "Full results saved to: $TRACE_DIR/$OUTPUT_FILE"
cat "$OUTPUT_FILE"

print_info ""
print_info "Key metrics to review:"
print_info "  - Waste Ratio: Percentage of buffer reads that were never used"
print_info "  - Overfetch Ratio: How much more data was read than applications requested"
print_info "  - Cache Efficiency: Percentage of buffer reads that were actually used"
print_info ""
print_info "If waste ratio is high (>25%), consider reducing cachebuffersize mount option"

