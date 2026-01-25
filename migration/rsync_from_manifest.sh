#!/usr/bin/env bash
set -euo pipefail

# Configurable paths
SRC_ROOT="/stornext/QUANTUM/"
DEST_ROOT="/pure/MM_Prod/QUANTUM/"
MANIFEST="/stornext/QUANTUM/.pure_migration/recovery/rclone_manifest.tsv"
MISSING_LIST="/stornext/QUANTUM/.pure_migration/recovery/missing_local_paths.txt"
OUT_LIST="/stornext/QUANTUM/.pure_migration/recovery/rsync_files.txt"

usage() {
  echo "Usage: $0 [--dry-run]"
  echo "Generates file list and runs rsync from \$SRC_ROOT to \$DEST_ROOT."
}

DRY_RUN=""
if [[ "${1-}" == "--dry-run" ]]; then
  DRY_RUN="--dry-run"
elif [[ "${1-}" != "" ]]; then
  usage
  exit 1
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
fi

# Build rsync file list (relative paths)
if [[ -f "$MISSING_LIST" ]]; then
  awk -F'\t' -v prefix="$SRC_ROOT" '
    NR==FNR {missing[$0]=1; next}
    ($1 in missing) {next}
    {
      path=$1
      sub("^" prefix, "", path)
      print path
    }
  ' "$MISSING_LIST" "$MANIFEST" > "$OUT_LIST"
else
  awk -F'\t' -v prefix="$SRC_ROOT" '
    {
      path=$1
      sub("^" prefix, "", path)
      print path
    }
  ' "$MANIFEST" > "$OUT_LIST"
fi

rsync -a --info=stats2,progress2 $DRY_RUN \
  --files-from="$OUT_LIST" \
  "$SRC_ROOT" "$DEST_ROOT"
