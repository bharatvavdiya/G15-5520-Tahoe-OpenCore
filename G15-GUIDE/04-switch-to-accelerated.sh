#!/bin/bash
# Makes the NEXT start use an ACCELERATED config (WhateverXe on). No sudo needed.
#   bash /Volumes/1401/G15-GUIDE/04-switch-to-accelerated.sh      -> A (default): official WhateverXe 0.8.3 + AMFIAnchor
#   bash /Volumes/1401/G15-GUIDE/04-switch-to-accelerated.sh A    -> A: WhateverXe 0.8.3 + AMFIAnchor (official method)
#   bash /Volumes/1401/G15-GUIDE/04-switch-to-accelerated.sh D    -> D: A + NVIDIA RTX 3050 turned off in macOS (SSDT-dGPU-Off)
#   bash /Volumes/1401/G15-GUIDE/04-switch-to-accelerated.sh N    -> N: WhateverXe 0.8.3 display only, no GPU acceleration (test)
#   bash /Volumes/1401/G15-GUIDE/04-switch-to-accelerated.sh C    -> C: old Nov 17 setup, WhateverXe 0.8.2 + AMFIPass Mod
#   bash /Volumes/1401/G15-GUIDE/04-switch-to-accelerated.sh B    -> B: WhateverXe 0.8.2 + AMFIAnchor
# Note (19 Nov): on the cleaned macOS, 0.8.2 (C) did not start the Intel GPU; 0.8.3 (A) did.
OC="$(cd "$(dirname "$0")/.." && pwd)/EFI/OC"
case "${1:-A}" in
  A|a) SRC=config-accel.plist;         NAME="A (WhateverXe 0.8.3 + AMFIAnchor)";;
  D|d) SRC=config-accel-dgpuoff.plist; NAME="D (A + NVIDIA dGPU off)";;
  N|n) SRC=config-accel-noaccel.plist; NAME="N (WhateverXe 0.8.3 display only, no GPU acceleration)";;
  C|c) SRC=config-accel-nov17.plist;   NAME="C (old Nov 17 setup: WhateverXe 0.8.2 + AMFIPass Mod)";;
  B|b) SRC=config-accel-082.plist;     NAME="B (WhateverXe 0.8.2 + AMFIAnchor)";;
  *) echo "STOP: use A, D, N, C or B. Nothing was changed."; exit 1;;
esac
[ -f "$OC/$SRC" ] || { echo "STOP: $OC/$SRC not found. Nothing was changed."; exit 1; }
cp -f "$OC/$SRC" "$OC/config.plist" && cmp -s "$OC/$SRC" "$OC/config.plist" \
  && echo "DONE: next start = $NAME." \
  || { echo "STOP: copy failed."; exit 1; }
