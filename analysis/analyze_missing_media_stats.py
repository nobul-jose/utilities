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

medium_re = re.compile(r"^\s*medium:\s*(\S+)")
seg_uuid_re = re.compile(r"^\s*seg_uuid:\s*(\S+)")
add_date_re = re.compile(r"^\s*add_date:\s*(\d+)")

missing_mediums = Counter()
missing_seg_uuid = Counter()
missing_add_date = Counter()
all_mediums = Counter()

for path, block in blocks.items():
    medium = None
    seg_uuid = None
    add_date = None
    for line in block:
        if medium is None:
            m = medium_re.search(line)
            if m:
                medium = m.group(1)
        if seg_uuid is None:
            m = seg_uuid_re.search(line)
            if m:
                seg_uuid = m.group(1)
        if add_date is None:
            m = add_date_re.search(line)
            if m:
                add_date = m.group(1)
    if medium:
        all_mediums[medium] += 1
    if path in missing:
        if medium:
            missing_mediums[medium] += 1
        if seg_uuid:
            missing_seg_uuid[seg_uuid] += 1
        if add_date:
            missing_add_date[add_date] += 1

print("Top missing media IDs:")
for med, cnt in missing_mediums.most_common(10):
    print(f"  {med}: {cnt}")

print("\nTop missing seg_uuid:")
for s, cnt in missing_seg_uuid.most_common(5):
    print(f"  {s}: {cnt}")

print("\nTop missing add_date (epoch):")
for d, cnt in missing_add_date.most_common(5):
    print(f"  {d}: {cnt}")

ratio = []
for med, cnt in missing_mediums.items():
    ratio.append((cnt / all_mediums.get(med, 1), med, cnt, all_mediums.get(med, 0)))
ratio.sort(reverse=True)

print("\nMissing share by medium (top 10 by ratio):")
for r, med, mcnt, acnt in ratio[:10]:
    print(f"  {med}: missing {mcnt} / total {acnt} ({r:.2%})")
