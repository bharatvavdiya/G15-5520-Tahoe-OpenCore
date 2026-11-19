#!/bin/bash
# Makes the NEXT start use a MAINTENANCE config (WhateverXe off: slow but no graphics hangs). No sudo needed.
#   bash /Volumes/1401/G15-GUIDE/05-switch-to-maintenance.sh        -> MAINTENANCE (normal)
#   bash /Volumes/1401/G15-GUIDE/05-switch-to-maintenance.sh safe   -> MAINTENANCE in Safe Mode (no add-on kexts at all)
#   bash /Volumes/1401/G15-GUIDE/05-switch-to-maintenance.sh ctr    -> old MAINTENANCE with the CPU topology kext ON
OC="$(cd "$(dirname "$0")/.." && pwd)/EFI/OC"
case "${1:-}" in
  "")        SRC=config-maintenance.plist;      NAME="MAINTENANCE (normal)";;
  safe|SAFE) SRC=config-maintenance-safe.plist; NAME="MAINTENANCE in Safe Mode";;
  ctr|CTR)   SRC=config-maintenance-ctr.plist;  NAME="old MAINTENANCE with the CPU topology kext ON";;
  *) echo "STOP: use no word, safe, or ctr. Nothing was changed."; exit 1;;
esac
[ -f "$OC/$SRC" ] || { echo "STOP: $OC/$SRC not found. Nothing was changed."; exit 1; }
cp -f "$OC/$SRC" "$OC/config.plist" && cmp -s "$OC/$SRC" "$OC/config.plist" \
  && echo "DONE: next start = $NAME." \
  || { echo "STOP: copy failed."; exit 1; }
