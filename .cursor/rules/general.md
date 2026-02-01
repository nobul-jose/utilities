# General Cursor Rules

## Project Context

This is a utilities repository with shell scripts and Python tools for system administration tasks.

## Code Standards

- Shell scripts: Use bash with strict mode (`set -euo pipefail`)
- Python: Python 3.6+ compatible, include docstrings
- Always include usage documentation in script headers

## Bug Fixing Approach

When fixing bugs:
1. First write a test that reproduces the bug
2. Then implement the fix
3. Verify with the passing test

## File Organization

Place new scripts in the appropriate directory:
- `analysis/` - Data analysis
- `conversion/` - Format conversion
- `migration/` - Data migration
- `monitoring/` - System monitoring
- `stornext/` - StorNext utilities
- `system/` - System utilities
- `testing/` - Testing utilities

## Dependencies

- Prefer standard library when possible
- Document any pip dependencies in script headers
- Common dependencies: `pypdf`, `anthropic`
