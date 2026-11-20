#!/bin/bash
# Collects the COMPLETE logs of the last hours (including frozen starts) for Claude. Changes nothing.
# Run in MAINTENANCE mode:  sudo bash /Volumes/1401/G15-GUIDE/08-freeze-logs.sh
# Optional: number of hours to look back (default 12, because the macOS clock can start 5:30 ahead after Windows), e.g.  sudo bash .../08-freeze-logs.sh 24
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
[ "$(id -u)" = 0 ] || { echo "STOP: run it with sudo:  sudo bash \"$0\""; exit 1; }
DIR="$(cd "$(dirname "$0")" && pwd)"
H=${1:-12}
case "$H" in ''|*[!0-9]*) H=12;; esac
OUT="$DIR/reports/freeze-logs-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT" || { echo "STOP: cannot write $OUT"; exit 1; }
echo "Collecting the last $H hours of logs (2-5 minutes; do not use the laptop)..."
{
  echo "=== collected $(date)"; sw_vers; uname -v
  echo "boot-args now: $(sysctl -n kern.bootargs 2>/dev/null)"
  echo "safe boot now: $(sysctl -n kern.safeboot 2>/dev/null)"
} > "$OUT/info.txt" 2>&1
echo "1/5 boot timeline"
log show --last "${H}h" --style compact --predicate 'eventMessage CONTAINS "Darwin Kernel Version" OR eventMessage CONTAINS "Previous shutdown cause" OR eventMessage CONTAINS "boot-args"' > "$OUT/boots.txt" 2>&1
echo "2/5 full kernel log"
log show --last "${H}h" --style compact --predicate 'process == "kernel"' 2>&1 | gzip -c > "$OUT/kernel.txt.gz"
echo "3/5 kext manager, WindowServer, login"
log show --last "${H}h" --style compact --predicate 'process == "kernelmanagerd" OR process == "kmutil" OR process == "WindowServer" OR process == "loginwindow" OR process == "syspolicyd"' 2>&1 | gzip -c > "$OUT/kextmanager-windowserver.txt.gz"
echo "4/5 current drivers and collections"
kmutil showloaded --list-only > "$OUT/loaded-now.txt" 2>&1
kmutil inspect -a x86_64 -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc > "$OUT/auxkc-contents.txt" 2>&1
ls -la /Library/KernelCollections /Library/Extensions /Library/GPUBundles /Library/StagedExtensions/Library/Extensions > "$OUT/folders.txt" 2>&1
system_profiler SPDisplaysDataType > "$OUT/displays-now.txt" 2>&1
pmset -g > "$OUT/pmset.txt" 2>&1
echo "5/5 crash and hang reports"
CU=$(stat -f %Su /dev/console 2>/dev/null); UH=$(eval echo "~$CU")
mkdir -p "$OUT/diag"
for d in /Library/Logs/DiagnosticReports "$UH/Library/Logs/DiagnosticReports"; do
  [ -d "$d" ] && find "$d" -maxdepth 2 -type f -mmin -$((H * 60)) -exec cp {} "$OUT/diag/" \; 2>/dev/null
done
sync
echo
echo "kernel.txt.gz: $(gzip -dc "$OUT/kernel.txt.gz" | wc -l | tr -d ' ') lines   reports copied: $(ls "$OUT/diag" | wc -l | tr -d ' ')"
echo "Graphics drivers loaded right now:"; grep -iE 'TGL|WhateverXe|AMFI' "$OUT/loaded-now.txt"
echo "DONE. Saved: $OUT"
echo "Now shut down, boot Windows and tell Claude: check logs"
