# Shell Scripting Skills

## Bash Best Practices

- Always use `#!/bin/bash` shebang
- Use `set -euo pipefail` for strict error handling
- Quote variables: `"$variable"` not `$variable`
- Use `[[ ]]` for conditionals instead of `[ ]`

## Error Handling Pattern

```bash
#!/bin/bash
set -euo pipefail

cleanup() {
    # Cleanup code here
    echo "Cleaning up..."
}
trap cleanup EXIT

main() {
    # Main logic here
    :
}

main "$@"
```

## Logging Pattern

```bash
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}
```

## Common Utilities in This Repo

- StorNext commands: `fsretrieve`, `cvdb`, `snseq`
- Multipath: `dmsetup`, `multipath`
- File operations: `rsync`, `find`, `xargs`
