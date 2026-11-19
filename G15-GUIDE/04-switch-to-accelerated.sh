#!/bin/bash
# Makes the NEXT start use an ACCELERATED config (WhateverXe on). No sudo needed.
#   bash /Volumes/1401/G15-GUIDE/04-switch-to-accelerated.sh      -> C (default): Nov 17 setup, the one proven stable
#   bash /Volumes/1401/G15-GUIDE/04-switch-to-accelerated.sh C    -> C: WhateverXe 0.8.2 + AMFIPass Mod
#   bash /Volumes/1401/G15-GUIDE/04-switch-to-accelerated.sh B    -> B: WhateverXe 0.8.2 + AMFIAnchor
#   bash /Volumes/1401/G15-GUIDE/04-switch-to-accelerated.sh A    -> A: WhateverXe 0.8.3 + AMFIAnchor
#   bash /Volumes/1401/G15-GUIDE/04-switch-to-accelerated.sh N    -> N: WhateverXe 0.8.3 display only, no GPU acceleration (test)
OC="$(cd "$(dirname "$0")/.." && pwd)/EFI/OC"
case "${1:-C}" in
  C|c) SRC=config-accel-nov17.plist;   NAME="C (Nov 17 setup: WhateverXe 0.8.2 + AMFIPass Mod)";;
  B|b) SRC=config-accel-082.plist;     NAME="B (WhateverXe 0.8.2 + AMFIAnchor)";;
  A|a) SRC=config-accel.plist;         NAME="A (WhateverXe 0.8.3 + AMFIAnchor)";;
  N|n) SRC=config-accel-noaccel.plist; NAME="N (WhateverXe 0.8.3 display only, no GPU acceleration)";;
  *) echo "STOP: use A, B, C or N. Nothing was changed."; exit 1;;
esac
[ -f "$OC/$SRC" ] || { echo "STOP: $OC/$SRC not found. Nothing was changed."; exit 1; }
cp -f "$OC/$SRC" "$OC/config.plist" && cmp -s "$OC/$SRC" "$OC/config.plist" \
  && echo "DONE: next start = $NAME." \
  || { echo "STOP: copy failed."; exit 1; }
