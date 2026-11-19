#!/bin/bash
# Makes the NEXT start use the MAINTENANCE config (WhateverXe off: slow but stable).
# Run:  bash /Volumes/1401/G15-GUIDE/05-switch-to-maintenance.sh   (no sudo needed)
OC="$(cd "$(dirname "$0")/.." && pwd)/EFI/OC"
[ -f "$OC/config-maintenance.plist" ] || { echo "STOP: $OC/config-maintenance.plist not found. Nothing was changed."; exit 1; }
cp -f "$OC/config-maintenance.plist" "$OC/config.plist" && cmp -s "$OC/config-maintenance.plist" "$OC/config.plist" \
  && echo "DONE: next start = MAINTENANCE (WhateverXe off)." \
  || { echo "STOP: copy failed."; exit 1; }
