#!/usr/bin/env python3
from pathlib import Path
import re
from datetime import datetime, timezone

base = Path("/Users/pepe/Library/CloudStorage/GoogleDrive-jose@nobul.tech/My Drive/Customers/marlins/pure migration/quantum/recovery/archive_files")
files = {
    "2019": base / "archive_2019_dm_info.txt",
    "2020": base / "archive_2020_dm_info.txt",
    "2022": base / "archive_2022_dm_info.txt",
}

# Missing window from earlier analysis (UTC)
missing_min = 1622676314  # 2021-06-02T23:25:14Z
missing_max = 1622706750  # 2021-06-03T07:52:30Z

add_date_re = re.compile(r"^\s*add_date:\s*(\d+)")

print("Missing window:")
print(f"  min: {missing_min} -> {datetime.fromtimestamp(missing_min, timezone.utc).isoformat()}")
print(f"  max: {missing_max} -> {datetime.fromtimestamp(missing_max, timezone.utc).isoformat()}")

print("\nPer-file counts relative to missing window:")
for label, path in files.items():
    if not path.exists():
        print(f"{label}: file not found: {path}")
        continue
    total = 0
    in_window = 0
    before_min = 0
    after_max = 0
    with path.open() as f:
        for line in f:
            m = add_date_re.search(line)
            if not m:
                continue
            ts = int(m.group(1))
            total += 1
            if missing_min <= ts <= missing_max:
                in_window += 1
            elif ts < missing_min:
                before_min += 1
            else:
                after_max += 1
    print(f"{label}: total add_date entries: {total}")
    print(f"  in window: {in_window}")
    print(f"  before window: {before_min}")
    print(f"  after window: {after_max}")

min_out = None
max_out = None
for path in files.values():
    if not path.exists():
        continue
    with path.open() as f:
        for line in f:
            m = add_date_re.search(line)
            if not m:
                continue
            ts = int(m.group(1))
            if missing_min <= ts <= missing_max:
                continue
            min_out = ts if min_out is None else min(min_out, ts)
            max_out = ts if max_out is None else max(max_out, ts)

print("\nOutside missing window:")
if min_out is None:
    print("  no add_date entries outside missing window")
else:
    print(f"  min: {min_out} -> {datetime.fromtimestamp(min_out, timezone.utc).isoformat()}")
    print(f"  max: {max_out} -> {datetime.fromtimestamp(max_out, timezone.utc).isoformat()}")
