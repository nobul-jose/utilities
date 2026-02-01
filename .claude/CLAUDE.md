# CLAUDE.md - Project Instructions for Claude

## Project Overview

This is a utilities repository containing shell scripts and Python utilities for system administration, data migration, monitoring, and document conversion tasks.

## Directory Structure

- `analysis/` - Data analysis scripts
- `conversion/` - Document format conversion tools
- `migration/` - Data migration and recovery scripts
- `monitoring/` - System monitoring and alerting scripts
- `stornext/` - StorNext filesystem-specific utilities
- `system/` - System-level utilities (multipath, etc.)
- `testing/` - API and development testing scripts

## Code Style Guidelines

- Shell scripts should use bash and include proper error handling
- Python scripts should be Python 3 compatible
- Include usage documentation in script headers
- Use meaningful variable names

## Bug Fixing Best Practice

> "When I report a bug, don't start by trying to fix it. Instead, start by writing a test that reproduces the bug. Then, have subagents try to fix the bug and prove it with a passing test."
> — Nathan Baschez (@nbaschez)

This test-first approach ensures:
1. The bug is clearly understood and reproducible
2. The fix can be verified objectively
3. Regression testing is built-in for the future

## Working with This Repository

- Many scripts require root privileges (StorNext, multipath)
- Check script headers for configuration options and dependencies
- Python dependencies: `pypdf`, `anthropic`

## Testing

- Always test scripts in a safe environment before production use
- For API scripts, use the testing utilities in `testing/` to validate credentials
