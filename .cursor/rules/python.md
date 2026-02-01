# Python Script Rules

## Required Header

All Python scripts must include:
```python
#!/usr/bin/env python3
"""
Script description.

Usage:
    python script.py [options] <args>

Requirements:
    pip install package1 package2
"""
```

## Argument Parsing

Use argparse for command-line arguments:
```python
import argparse

parser = argparse.ArgumentParser(description="Description")
parser.add_argument("input", help="Input file")
parser.add_argument("-o", "--output", help="Output file")
args = parser.parse_args()
```

## Error Handling

- Print errors to stderr: `print("Error", file=sys.stderr)`
- Use appropriate exit codes
- Catch specific exceptions, not bare `except:`

## File Paths

Use pathlib for file operations:
```python
from pathlib import Path

path = Path(args.input)
if not path.exists():
    sys.exit(f"File not found: {path}")
```
