#!/usr/bin/env python3
from pathlib import Path
import re
from collections import Counter

missing_path = Path("/Users/pepe/Library/CloudStorage/GoogleDrive-jose@nobul.tech/My Drive/Customers/marlins/pure migration/quantum/recovery/archive_files/missing_local_paths.txt")
dm_info_path = Path("/Users/pepe/Library/CloudStorage/GoogleDrive-jose@nobul.tech/My Drive/Customers/marlins/pure migration/quantum/recovery/archive_files/archive_2020_dm_info.txt")

missing = set(p.strip() for p in missing_path.read_text().splitlines() if p.strip())

blocks = {}
current = None
lines = []

with dm_info_path.open() as f:
    for line in f:
        if line.startswith("Filename:"):
            if current is not None:
                blocks[current] = lines
            current = line.split("Filename:", 1)[1].strip()
            lines = [line.rstrip("\n")]
        elif current is not None:
            lines.append(line.rstrip("\n"))
    if current is not None:
        blocks[current] = lines

missing_blocks = {k: v for k, v in blocks.items() if k in missing}

field_patterns = {
    "flags": re.compile(r"^\s*flags:\s*(.*)$"),
    "cpymap": re.compile(r"cpymap:\s*([^\s]+)"),
    "class": re.compile(r"\bclass:\s*(\S+)"),
    "vsn": re.compile(r"\bvsn:\s*(\S+)"),
    "totvers": re.compile(r"\btotvers:\s*(\S+)"),
    "stub": re.compile(r"stub size,len:\s*([^,]+),([^\s]+)"),
}

counts = {k: Counter() for k in field_patterns}
flags_all_copies = Counter()

for path, block in missing_blocks.items():
    text = "\n".join(block)
    for key, pat in field_patterns.items():
        m = pat.search(text)
        if m:
            if key == "stub":
                val = f"{m.group(1).strip()},{m.group(2).strip()}"
            else:
                val = m.group(1).strip()
            counts[key][val] += 1
    if "ALL_COPIES_MADE" in text:
        flags_all_copies["ALL_COPIES_MADE"] += 1
    else:
        flags_all_copies["NO_ALL_COPIES_MADE"] += 1

print(f"Missing paths: {len(missing)}")
print(f"Missing paths with dm_info block: {len(missing_blocks)}")

print("\nFlag ALL_COPIES_MADE presence:")
for k, v in flags_all_copies.items():
    print(f"  {k}: {v}")

print("\nTop flags values (first 'flags:' line):")
for val, cnt in counts["flags"].most_common(5):
    print(f"  {val}: {cnt}")

print("\nTop cpymap values:")
for val, cnt in counts["cpymap"].most_common(5):
    print(f"  {val}: {cnt}")

print("\nTop class values:")
for val, cnt in counts["class"].most_common(5):
    print(f"  {val}: {cnt}")

print("\nTop stub size,len values:")
for val, cnt in counts["stub"].most_common(5):
    print(f"  {val}: {cnt}")

missing_without_dm = [p for p in missing if p not in blocks]
if missing_without_dm:
    print("\nMissing paths NOT found in dm_info:")
    for p in missing_without_dm[:10]:
        print(f"  {p}")
    if len(missing_without_dm) > 10:
        print(f"  ... {len(missing_without_dm) - 10} more")
