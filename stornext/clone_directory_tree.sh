#!/bin/bash
#
# clone_directory_tree.sh
#
# Recreates a directory tree structure with all metadata (permissions, ownership,
# timestamps, ACLs, extended attributes) from source to destination.
# Does NOT copy files - only directories and their metadata.
#
# Usage: ./clone_directory_tree.sh <source_dir> <dest_dir> [options]
#
# Options:
#   -v, --verbose       Show detailed progress
#   -d, --dry-run       Show what would be done without actually doing it
#   -a, --acls          Copy ACLs (requires getfacl/setfacl)
#   -x, --xattrs        Copy extended attributes (requires getfattr/setfattr)
#   -l, --log FILE      Log output to file
#   -h, --help          Show this help message
#

set -o pipefail

# Default values
VERBOSE=0
DRY_RUN=0
COPY_ACLS=0
COPY_XATTRS=0
LOG_FILE=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_DIRS=0
SUCCESS_COUNT=0
FAIL_COUNT=0

usage() {
    cat << EOF
Usage: $(basename "$0") <source_dir> <dest_dir> [options]

Recreates a directory tree structure with all metadata from source to destination.
Only directories are created - files are NOT copied.

Arguments:
    source_dir      Source directory to clone structure from
    dest_dir        Destination directory (will be created if needed)

Options:
    -v, --verbose       Show detailed progress
    -d, --dry-run       Show what would be done without actually doing it
    -a, --acls          Copy ACLs (requires getfacl/setfacl)
    -x, --xattrs        Copy extended attributes (requires getfattr/setfattr)
    -l, --log FILE      Log output to file
    -h, --help          Show this help message

Metadata copied:
    - Directory permissions (mode)
    - Ownership (user and group)
    - Timestamps (atime, mtime)
    - ACLs (with -a option)
    - Extended attributes (with -x option)

Examples:
    # Basic usage - clone directory structure
    $(basename "$0") /stornext/managed/project1 /local/backup/project1

    # Verbose with logging
    $(basename "$0") -v -l clone.log /source/data /dest/data

    # Include ACLs and extended attributes
    $(basename "$0") -a -x /source/data /dest/data

    # Dry run to preview
    $(basename "$0") -d -v /source/test /dest/test

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

check_prerequisites() {
    # Check for required commands
    if [[ "$COPY_ACLS" -eq 1 ]]; then
        if ! command -v getfacl &> /dev/null || ! command -v setfacl &> /dev/null; then
            log ERROR "ACL tools (getfacl/setfacl) not found. Install acl package or remove -a option."
            exit 1
        fi
    fi
    
    if [[ "$COPY_XATTRS" -eq 1 ]]; then
        if ! command -v getfattr &> /dev/null || ! command -v setfattr &> /dev/null; then
            log ERROR "Extended attribute tools (getfattr/setfattr) not found. Install attr package or remove -x option."
            exit 1
        fi
    fi
}

clone_directory() {
    local src_dir="$1"
    local dest_dir="$2"
    
    # Create the directory
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log DEBUG "Would create: $dest_dir"
    else
        if ! mkdir -p "$dest_dir" 2>/dev/null; then
            log ERROR "Failed to create directory: $dest_dir"
            return 1
        fi
    fi
    
    # Get source metadata using stat
    # Linux stat format
    local mode owner group atime mtime
    
    if stat --version &>/dev/null 2>&1; then
        # GNU stat (Linux)
        mode=$(stat -c '%a' "$src_dir" 2>/dev/null)
        owner=$(stat -c '%U' "$src_dir" 2>/dev/null)
        group=$(stat -c '%G' "$src_dir" 2>/dev/null)
        atime=$(stat -c '%X' "$src_dir" 2>/dev/null)
        mtime=$(stat -c '%Y' "$src_dir" 2>/dev/null)
    else
        # BSD stat (macOS)
        mode=$(stat -f '%Lp' "$src_dir" 2>/dev/null)
        owner=$(stat -f '%Su' "$src_dir" 2>/dev/null)
        group=$(stat -f '%Sg' "$src_dir" 2>/dev/null)
        atime=$(stat -f '%a' "$src_dir" 2>/dev/null)
        mtime=$(stat -f '%m' "$src_dir" 2>/dev/null)
    fi
    
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log DEBUG "  Mode: $mode, Owner: $owner:$group, mtime: $mtime"
    else
        # Apply permissions
        if [[ -n "$mode" ]]; then
            chmod "$mode" "$dest_dir" 2>/dev/null || log WARN "Failed to set mode on $dest_dir"
        fi
        
        # Apply ownership (requires root)
        if [[ -n "$owner" ]] && [[ -n "$group" ]]; then
            if [[ $EUID -eq 0 ]]; then
                chown "$owner:$group" "$dest_dir" 2>/dev/null || log WARN "Failed to set ownership on $dest_dir"
            fi
        fi
        
        # Apply timestamps
        if [[ -n "$atime" ]] && [[ -n "$mtime" ]]; then
            # Use touch with reference or explicit times
            touch -r "$src_dir" "$dest_dir" 2>/dev/null || {
                # Fallback: try to set mtime at least
                touch -d "@$mtime" "$dest_dir" 2>/dev/null
            }
        fi
        
        # Copy ACLs if requested
        if [[ "$COPY_ACLS" -eq 1 ]]; then
            getfacl -p "$src_dir" 2>/dev/null | setfacl --set-file=- "$dest_dir" 2>/dev/null || \
                log DEBUG "No ACLs or failed to copy ACLs for $dest_dir"
        fi
        
        # Copy extended attributes if requested
        if [[ "$COPY_XATTRS" -eq 1 ]]; then
            # Get list of xattrs and copy each one
            local xattrs=$(getfattr -d -m '.*' --only-values "$src_dir" 2>/dev/null)
            if [[ -n "$xattrs" ]]; then
                getfattr -d -m '.*' "$src_dir" 2>/dev/null | setfattr --restore=- 2>/dev/null || \
                    log DEBUG "Failed to copy xattrs for $dest_dir"
            fi
        fi
    fi
    
    return 0
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
            -a|--acls)
                COPY_ACLS=1
                shift
                ;;
            -x|--xattrs)
                COPY_XATTRS=1
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
    
    # Validate source
    if [[ ! -d "$SRC_DIR" ]]; then
        log ERROR "Source directory does not exist: $SRC_DIR"
        exit 1
    fi
    
    log INFO "=========================================="
    log INFO "Clone Directory Tree"
    log INFO "=========================================="
    log INFO "Source:      $SRC_DIR"
    log INFO "Destination: $DEST_DIR"
    [[ "$COPY_ACLS" -eq 1 ]] && log INFO "Copy ACLs:   Yes"
    [[ "$COPY_XATTRS" -eq 1 ]] && log INFO "Copy xattrs: Yes"
    [[ "$DRY_RUN" -eq 1 ]] && log WARN "DRY RUN MODE - No changes will be made"
    log INFO "=========================================="
    
    # Check prerequisites
    check_prerequisites
    
    # Count directories first
    log INFO "Scanning source directory..."
    TOTAL_DIRS=$(find "$SRC_DIR" -type d 2>/dev/null | wc -l)
    log INFO "Found $TOTAL_DIRS directories to process"
    
    if [[ $TOTAL_DIRS -eq 0 ]]; then
        log WARN "No directories found in source"
        exit 0
    fi
    
    # Process directories in order (sorted to ensure parents created before children)
    local processed=0
    
    while IFS= read -r src_subdir; do
        # Calculate relative path
        local rel_path="${src_subdir#$SRC_DIR}"
        rel_path="${rel_path#/}"  # Remove leading slash
        
        # Build destination path
        local dest_subdir
        if [[ -z "$rel_path" ]]; then
            dest_subdir="$DEST_DIR"
        else
            dest_subdir="$DEST_DIR/$rel_path"
        fi
        
        # Clone the directory
        if clone_directory "$src_subdir" "$dest_subdir"; then
            ((SUCCESS_COUNT++))
            [[ "$VERBOSE" -eq 1 ]] && log DEBUG "Created: $dest_subdir"
        else
            ((FAIL_COUNT++))
        fi
        
        ((processed++))
        
        # Progress update every 100 directories or at the end
        if [[ $((processed % 100)) -eq 0 ]] || [[ $processed -eq $TOTAL_DIRS ]]; then
            log INFO "Progress: $processed / $TOTAL_DIRS directories"
        fi
        
    done < <(find "$SRC_DIR" -type d 2>/dev/null | sort)
    
    # Summary
    log INFO "=========================================="
    log INFO "SUMMARY"
    log INFO "=========================================="
    log INFO "Total directories: $TOTAL_DIRS"
    log INFO "Successful:        $SUCCESS_COUNT"
    log INFO "Failed:            $FAIL_COUNT"
    log INFO "=========================================="
    
    if [[ $FAIL_COUNT -gt 0 ]]; then
        log WARN "Some directories failed. Check the log for details."
        exit 1
    fi
    
    log INFO "Done! Directory tree cloned successfully."
    exit 0
}

main "$@"


