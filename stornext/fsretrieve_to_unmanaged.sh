#!/bin/bash
#
# fsretrieve_to_unmanaged.sh
# 
# Recursively retrieves files from a managed StorNext directory to an unmanaged location.
# This creates a copy of files in a non-managed directory, preserving the directory structure.
#
# Usage: ./fsretrieve_to_unmanaged.sh <source_dir> <dest_dir> [options]
#
# Options:
#   -v, --verbose       Show detailed progress
#   -d, --dry-run       Show what would be done without actually doing it
#   -p, --parallel N    Number of parallel retrieve operations (default: 4)
#   -c, --copy N        Retrieve specific copy number (1, 2, etc.)
#   -g, --glacier TYPE  Glacier restore type: standard, expedited, bulk
#   -f, --force         Overwrite existing files in destination
#   -l, --log FILE      Log output to file
#   -h, --help          Show this help message
#

set -o pipefail

# Default values
VERBOSE=0
DRY_RUN=0
PARALLEL=4
COPY_NUM=""
GLACIER_TYPE=""
FORCE=0
LOG_FILE=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_FILES=0
SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0
TOTAL_BYTES=0

# Temp files for parallel processing
TEMP_DIR=""

usage() {
    cat << EOF
Usage: $(basename "$0") <source_dir> <dest_dir> [options]

Recursively retrieves files from a managed StorNext directory to an unmanaged location.
The destination directory must NOT be under a Storage Manager relation point.

Arguments:
    source_dir      Source directory (must be a managed directory)
    dest_dir        Destination directory (must be an unmanaged location)

Options:
    -v, --verbose       Show detailed progress
    -d, --dry-run       Show what would be done without actually doing it
    -p, --parallel N    Number of parallel retrieve operations (default: 4)
    -c, --copy N        Retrieve specific copy number (1, 2, etc.)
    -g, --glacier TYPE  Glacier restore type: standard, expedited, bulk
    -f, --force         Overwrite existing files in destination
    -l, --log FILE      Log output to file
    -h, --help          Show this help message

Examples:
    # Basic usage
    $(basename "$0") /stornext/managed/project1 /local/backup/project1

    # Verbose with logging
    $(basename "$0") -v -l retrieve.log /stornext/managed/data /mnt/unmanaged/data

    # Parallel with specific copy
    $(basename "$0") -p 8 -c 1 /stornext/managed/archive /backup/archive

    # Dry run to see what would happen
    $(basename "$0") -d -v /stornext/managed/test /tmp/test

EOF
    exit 1
}

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)    color="$GREEN" ;;
        WARN)    color="$YELLOW" ;;
        ERROR)   color="$RED" ;;
        DEBUG)   color="$BLUE" ;;
        *)       color="$NC" ;;
    esac
    
    if [[ "$VERBOSE" -eq 1 ]] || [[ "$level" != "DEBUG" ]]; then
        echo -e "${color}[$timestamp] [$level] $msg${NC}"
    fi
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    fi
}

cleanup() {
    if [[ -n "$TEMP_DIR" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT

check_prerequisites() {
    # Check if fsretrieve exists
    if ! command -v fsretrieve &> /dev/null; then
        log ERROR "fsretrieve command not found. Is StorNext installed?"
        exit 1
    fi
    
    # Check if fsfileinfo exists (for checking file status)
    if ! command -v fsfileinfo &> /dev/null; then
        log ERROR "fsfileinfo command not found. Is StorNext installed?"
        exit 1
    fi
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log WARN "Not running as root. Some operations may fail."
    fi
}

check_source_managed() {
    local src="$1"
    
    # Check if source exists
    if [[ ! -d "$src" ]]; then
        log ERROR "Source directory does not exist: $src"
        exit 1
    fi
    
    # Try to get file info on a file in the source to verify it's managed
    local test_file=$(find "$src" -type f -print -quit 2>/dev/null)
    if [[ -n "$test_file" ]]; then
        if ! fsfileinfo "$test_file" &> /dev/null; then
            log WARN "Source may not be a managed directory: $src"
        fi
    fi
}

check_dest_unmanaged() {
    local dest="$1"
    
    # Create destination if it doesn't exist
    if [[ ! -d "$dest" ]]; then
        log INFO "Creating destination directory: $dest"
        if [[ "$DRY_RUN" -eq 0 ]]; then
            mkdir -p "$dest" || {
                log ERROR "Failed to create destination directory: $dest"
                exit 1
            }
        fi
    fi
    
    # Check if destination is NOT managed (fsfileinfo should fail or show unmanaged)
    # Create a temporary test file
    local test_file="$dest/.fsretrieve_test_$$"
    if [[ "$DRY_RUN" -eq 0 ]]; then
        touch "$test_file" 2>/dev/null
        if fsfileinfo "$test_file" 2>/dev/null | grep -q "class index"; then
            rm -f "$test_file"
            log ERROR "Destination appears to be a managed directory!"
            log ERROR "Please specify an unmanaged destination path."
            exit 1
        fi
        rm -f "$test_file"
    fi
}

get_file_status() {
    local file="$1"
    
    # Use fsfileinfo to check if file is on disk or needs retrieval
    local info=$(fsfileinfo "$file" 2>/dev/null)
    
    if echo "$info" | grep -q "exists on disk: no"; then
        echo "truncated"
    elif echo "$info" | grep -q "exists on disk: yes"; then
        echo "ondisk"
    elif echo "$info" | grep -q "not stored"; then
        echo "notstored"
    else
        echo "unknown"
    fi
}

retrieve_file() {
    local src_file="$1"
    local dest_file="$2"
    local result_file="$3"
    
    local status="success"
    local msg=""
    
    # Check if destination already exists
    if [[ -f "$dest_file" ]] && [[ "$FORCE" -eq 0 ]]; then
        status="skipped"
        msg="destination exists"
        echo "$status:$msg" > "$result_file"
        return 0
    fi
    
    # Create destination directory
    local dest_dir=$(dirname "$dest_file")
    mkdir -p "$dest_dir" 2>/dev/null
    
    # Build fsretrieve command
    local cmd="fsretrieve"
    
    if [[ -n "$COPY_NUM" ]]; then
        cmd="$cmd -c $COPY_NUM"
    fi
    
    if [[ -n "$GLACIER_TYPE" ]]; then
        cmd="$cmd -g $GLACIER_TYPE"
    fi
    
    cmd="$cmd -n \"$dest_file\" \"$src_file\""
    
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log DEBUG "Would run: $cmd"
        status="dryrun"
        msg="would retrieve"
    else
        # Execute retrieve
        local output
        output=$(eval $cmd 2>&1)
        local rc=$?
        
        if [[ $rc -eq 0 ]]; then
            status="success"
            msg="retrieved"
            
            # Preserve permissions and timestamps
            local src_mode=$(stat -c '%a' "$src_file" 2>/dev/null || stat -f '%Lp' "$src_file" 2>/dev/null)
            local src_owner=$(stat -c '%U:%G' "$src_file" 2>/dev/null || stat -f '%Su:%Sg' "$src_file" 2>/dev/null)
            
            if [[ -n "$src_mode" ]]; then
                chmod "$src_mode" "$dest_file" 2>/dev/null
            fi
            if [[ -n "$src_owner" ]] && [[ $EUID -eq 0 ]]; then
                chown "$src_owner" "$dest_file" 2>/dev/null
            fi
            
            # Copy mtime
            touch -r "$src_file" "$dest_file" 2>/dev/null
        else
            status="failed"
            msg="$output"
        fi
    fi
    
    echo "$status:$msg" > "$result_file"
}

copy_ondisk_file() {
    local src_file="$1"
    local dest_file="$2"
    local result_file="$3"
    
    local status="success"
    local msg=""
    
    # Check if destination already exists
    if [[ -f "$dest_file" ]] && [[ "$FORCE" -eq 0 ]]; then
        status="skipped"
        msg="destination exists"
        echo "$status:$msg" > "$result_file"
        return 0
    fi
    
    # Create destination directory
    local dest_dir=$(dirname "$dest_file")
    mkdir -p "$dest_dir" 2>/dev/null
    
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log DEBUG "Would copy: $src_file -> $dest_file"
        status="dryrun"
        msg="would copy"
    else
        # File is on disk, just copy it
        if cp -p "$src_file" "$dest_file" 2>/dev/null; then
            status="success"
            msg="copied"
        else
            status="failed"
            msg="copy failed"
        fi
    fi
    
    echo "$status:$msg" > "$result_file"
}

process_file() {
    local src_file="$1"
    local src_base="$2"
    local dest_base="$3"
    local result_file="$4"
    
    # Calculate relative path and destination
    local rel_path="${src_file#$src_base}"
    rel_path="${rel_path#/}"  # Remove leading slash
    local dest_file="$dest_base/$rel_path"
    
    # Get file status
    local file_status=$(get_file_status "$src_file")
    
    case "$file_status" in
        truncated)
            # File needs to be retrieved from media
            retrieve_file "$src_file" "$dest_file" "$result_file"
            ;;
        ondisk)
            # File is on disk, copy it directly
            copy_ondisk_file "$src_file" "$dest_file" "$result_file"
            ;;
        notstored)
            # File hasn't been stored yet, just copy it
            copy_ondisk_file "$src_file" "$dest_file" "$result_file"
            ;;
        *)
            # Unknown status, try copy first, then retrieve
            if [[ -f "$src_file" ]] && [[ -s "$src_file" ]]; then
                copy_ondisk_file "$src_file" "$dest_file" "$result_file"
            else
                retrieve_file "$src_file" "$dest_file" "$result_file"
            fi
            ;;
    esac
}

main() {
    # Parse arguments
    local POSITIONAL=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=1
                shift
                ;;
            -p|--parallel)
                PARALLEL="$2"
                shift 2
                ;;
            -c|--copy)
                COPY_NUM="$2"
                shift 2
                ;;
            -g|--glacier)
                GLACIER_TYPE="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=1
                shift
                ;;
            -l|--log)
                LOG_FILE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            -*)
                log ERROR "Unknown option: $1"
                usage
                ;;
            *)
                POSITIONAL+=("$1")
                shift
                ;;
        esac
    done
    
    # Check positional arguments
    if [[ ${#POSITIONAL[@]} -lt 2 ]]; then
        log ERROR "Missing required arguments"
        usage
    fi
    
    local SRC_DIR="${POSITIONAL[0]}"
    local DEST_DIR="${POSITIONAL[1]}"
    
    # Remove trailing slashes
    SRC_DIR="${SRC_DIR%/}"
    DEST_DIR="${DEST_DIR%/}"
    
    log INFO "=========================================="
    log INFO "StorNext Retrieve to Unmanaged Directory"
    log INFO "=========================================="
    log INFO "Source:      $SRC_DIR"
    log INFO "Destination: $DEST_DIR"
    log INFO "Parallel:    $PARALLEL"
    [[ -n "$COPY_NUM" ]] && log INFO "Copy:        $COPY_NUM"
    [[ -n "$GLACIER_TYPE" ]] && log INFO "Glacier:     $GLACIER_TYPE"
    [[ "$DRY_RUN" -eq 1 ]] && log WARN "DRY RUN MODE - No changes will be made"
    log INFO "=========================================="
    
    # Prerequisites
    check_prerequisites
    check_source_managed "$SRC_DIR"
    check_dest_unmanaged "$DEST_DIR"
    
    # Create temp directory for results
    TEMP_DIR=$(mktemp -d)
    
    # Find all files
    log INFO "Scanning source directory..."
    local files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$SRC_DIR" -type f -print0 2>/dev/null)
    
    TOTAL_FILES=${#files[@]}
    log INFO "Found $TOTAL_FILES files to process"
    
    if [[ $TOTAL_FILES -eq 0 ]]; then
        log WARN "No files found in source directory"
        exit 0
    fi
    
    # Create directory structure first
    log INFO "Creating directory structure..."
    while IFS= read -r -d '' dir; do
        local rel_dir="${dir#$SRC_DIR}"
        rel_dir="${rel_dir#/}"
        local dest_subdir="$DEST_DIR/$rel_dir"
        
        if [[ "$DRY_RUN" -eq 0 ]]; then
            mkdir -p "$dest_subdir" 2>/dev/null
            # Copy directory permissions
            local dir_mode=$(stat -c '%a' "$dir" 2>/dev/null || stat -f '%Lp' "$dir" 2>/dev/null)
            if [[ -n "$dir_mode" ]]; then
                chmod "$dir_mode" "$dest_subdir" 2>/dev/null
            fi
        else
            log DEBUG "Would create: $dest_subdir"
        fi
    done < <(find "$SRC_DIR" -type d -print0 2>/dev/null)
    
    # Process files in parallel
    log INFO "Processing files..."
    local processed=0
    local pids=()
    
    for file in "${files[@]}"; do
        # Limit parallel processes
        while [[ ${#pids[@]} -ge $PARALLEL ]]; do
            # Wait for any process to finish
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    unset 'pids[i]'
                fi
            done
            pids=("${pids[@]}")  # Compact array
            sleep 0.1
        done
        
        # Create result file
        local result_file="$TEMP_DIR/result_$processed"
        
        # Process file in background
        (
            process_file "$file" "$SRC_DIR" "$DEST_DIR" "$result_file"
        ) &
        pids+=($!)
        
        ((processed++))
        
        # Progress update
        if [[ $((processed % 100)) -eq 0 ]] || [[ $processed -eq $TOTAL_FILES ]]; then
            log INFO "Progress: $processed / $TOTAL_FILES files"
        fi
    done
    
    # Wait for remaining processes
    wait
    
    # Collect results
    log INFO "Collecting results..."
    for ((i=0; i<TOTAL_FILES; i++)); do
        local result_file="$TEMP_DIR/result_$i"
        if [[ -f "$result_file" ]]; then
            local result=$(cat "$result_file")
            local status="${result%%:*}"
            
            case "$status" in
                success|dryrun)
                    ((SUCCESS_COUNT++))
                    ;;
                skipped)
                    ((SKIP_COUNT++))
                    ;;
                failed)
                    ((FAIL_COUNT++))
                    local msg="${result#*:}"
                    log ERROR "Failed: ${files[$i]} - $msg"
                    ;;
            esac
        fi
    done
    
    # Summary
    log INFO "=========================================="
    log INFO "SUMMARY"
    log INFO "=========================================="
    log INFO "Total files:  $TOTAL_FILES"
    log INFO "Successful:   $SUCCESS_COUNT"
    log INFO "Skipped:      $SKIP_COUNT"
    log INFO "Failed:       $FAIL_COUNT"
    log INFO "=========================================="
    
    if [[ $FAIL_COUNT -gt 0 ]]; then
        log WARN "Some files failed to process. Check the log for details."
        exit 1
    fi
    
    log INFO "Done!"
    exit 0
}

main "$@"


