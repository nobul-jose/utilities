#!/bin/bash

# Script to execute a command against each directory in small_archive_dirs.txt
# Usage: ./run_on_dirs.sh <command_template>
#
# Use {} as a placeholder for the full directory path
#
# Examples:
#   ./run_on_dirs.sh 'fsretrieve -R "{}"'
#   ./run_on_dirs.sh 'mv "{}" /path/to/new_dir/'
#   ./run_on_dirs.sh 'ls -la "{}"'
#   ./run_on_dirs.sh 'du -sh "{}"'

BASE_PATH="/stornext/QUANTUM/Archive"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIRS_FILE="${SCRIPT_DIR}/small_archive_dirs.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if command template was provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: No command template provided${NC}"
    echo ""
    echo "Usage: $0 <command_template>"
    echo ""
    echo "Use {} as a placeholder for the full directory path."
    echo ""
    echo "Examples:"
    echo "  $0 'fsretrieve -R \"{}\"'"
    echo "  $0 'mv \"{}\" /path/to/destination/'"
    echo "  $0 'ls -la \"{}\"'"
    echo "  $0 'du -sh \"{}\"'"
    exit 1
fi

# Check if dirs file exists
if [ ! -f "$DIRS_FILE" ]; then
    echo -e "${RED}Error: Directory list file not found: ${DIRS_FILE}${NC}"
    exit 1
fi

COMMAND_TEMPLATE="$1"
TOTAL=0
SUCCESS=0
FAILED=0

echo "========================================"
echo "Command template: $COMMAND_TEMPLATE"
echo "Base path: $BASE_PATH"
echo "========================================"
echo ""

# Read directories line by line
while IFS= read -r dir || [ -n "$dir" ]; do
    # Skip empty lines
    [ -z "$dir" ] && continue
    
    # Build full path
    FULL_PATH="${BASE_PATH}/${dir}"
    
    # Replace {} with the full path (properly quoted)
    CMD="${COMMAND_TEMPLATE//\{\}/$FULL_PATH}"
    
    ((TOTAL++))
    
    echo -e "${YELLOW}[$TOTAL] Executing:${NC} $CMD"
    
    # Execute the command
    if eval "$CMD"; then
        echo -e "${GREEN}    ✓ Success${NC}"
        ((SUCCESS++))
    else
        echo -e "${RED}    ✗ Failed (exit code: $?)${NC}"
        ((FAILED++))
    fi
    echo ""
    
done < "$DIRS_FILE"

echo "========================================"
echo "Summary:"
echo "  Total:   $TOTAL"
echo -e "  ${GREEN}Success: $SUCCESS${NC}"
echo -e "  ${RED}Failed:  $FAILED${NC}"
echo "========================================"
