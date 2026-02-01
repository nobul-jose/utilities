# Shell Script Rules

## Required Header

All shell scripts must include:
```bash
#!/bin/bash
# Description: Brief description of what this script does
# Usage: script.sh [options] <args>
# Requirements: List any dependencies
```

## Error Handling

Always use strict mode at the top of scripts:
```bash
set -euo pipefail
```

## Variables

- Quote all variable expansions: `"$var"`
- Use lowercase for local variables
- Use UPPERCASE for environment variables and constants

## Functions

- Use `local` for function-scoped variables
- Return meaningful exit codes
- Include cleanup with trap when necessary

## Permissions

Many scripts need root. Check and fail early:
```bash
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
fi
```
