# Python Scripting Skills

## Python Best Practices

- Use Python 3.6+ features
- Include docstrings for functions and modules
- Use type hints where appropriate
- Handle exceptions gracefully

## Script Template

```python
#!/usr/bin/env python3
"""
Script description here.

Usage:
    python script.py [options] <args>
"""

import argparse
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="Script description")
    parser.add_argument("input", help="Input file or directory")
    parser.add_argument("-o", "--output", help="Output file")
    parser.add_argument("-v", "--verbose", action="store_true")

    args = parser.parse_args()

    # Main logic here


if __name__ == "__main__":
    main()
```

## Common Patterns

### File Processing
```python
from pathlib import Path

input_path = Path(args.input)
if input_path.is_file():
    process_file(input_path)
elif input_path.is_dir():
    for file in input_path.rglob("*.txt"):
        process_file(file)
```

### Error Handling
```python
try:
    result = risky_operation()
except SpecificError as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
```
