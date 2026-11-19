#!/bin/bash
# Makes the NEXT start use a MAINTENANCE config (WhateverXe off: slow but no graphics hangs). No sudo needed.
#   bash /Volumes/1401/G15-GUIDE/05-switch-to-maintenance.sh         -> MAINTENANCE
#   bash /Volumes/1401/G15-GUIDE/05-switch-to-maintenance.sh noctr   -> MAINTENANCE without the CPU topology kext (test)
OC="$(cd "$(dirname "$0")/.." && pwd)/EFI/OC"
case "${1:-}" in
  "") SRC=config-maintenance.plist;       NAME="MAINTENANCE (WhateverXe off)";;
  noctr|NOCTR) SRC=config-maintenance-noctr.plist; NAME="MAINTENANCE without the CPU topology kext";;
  *) echo "STOP: use no word, or noctr. Nothing was changed."; exit 1;;
esac
[ -f "$OC/$SRC" ] || { echo "STOP: $OC/$SRC not found. Nothing was changed."; exit 1; }
cp -f "$OC/$SRC" "$OC/config.plist" && cmp -s "$OC/$SRC" "$OC/config.plist" \
  && echo "DONE: next start = $NAME." \
  || { echo "STOP: copy failed."; exit 1; }
