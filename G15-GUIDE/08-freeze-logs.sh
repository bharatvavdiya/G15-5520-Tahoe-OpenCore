#!/bin/bash
# Collects the COMPLETE logs of the last hours (including frozen starts) for Claude. Changes nothing.
# Run in MAINTENANCE mode:  sudo bash /Volumes/1401/G15-GUIDE/08-freeze-logs.sh
# Run it at the FIRST macOS start after the freeze. Optional: number of hours to look back (default 12; the steps use 24), e.g.  sudo bash .../08-freeze-logs.sh 24
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
echo "1/6 boot timeline"
log show --last "${H}h" --style compact --predicate 'eventMessage CONTAINS "Darwin Kernel Version" OR eventMessage CONTAINS "Previous shutdown cause" OR eventMessage CONTAINS "boot-args"' > "$OUT/boots.txt" 2>&1
echo "2/6 full kernel log"
log show --last "${H}h" --style compact --predicate 'process == "kernel"' 2>&1 | gzip -c > "$OUT/kernel.txt.gz"
echo "3/6 kext manager, WindowServer, login"
log show --last "${H}h" --style compact --predicate 'process == "kernelmanagerd" OR process == "kmutil" OR process == "WindowServer" OR process == "loginwindow" OR process == "syspolicyd"' 2>&1 | gzip -c > "$OUT/kextmanager-windowserver.txt.gz"
echo "4/6 all apps and services, last 10 minutes before the previous macOS session stopped"
# log show lists starts in boot order even when a start was stamped with a wrong clock, so use file order, not
# clock times. Each start begins with a few kernel lines stamped the same second as its "Darwin Kernel Version"
# line; the previous session ended at the last kernel line before that block. Empty = no earlier session here.
LE=""; WS=""; WE=""
LE=$(gzip -dc "$OUT/kernel.txt.gz" 2>/dev/null | awk '/^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]/ { s = substr($0, 1, 19); if (index($0, "Darwin Kernel Version")) e = p; if (s != c) { p = c; c = s } } END { print e }')
if [ -n "$LE" ]; then
  WS=$(date -j -v-10M -f '%Y-%m-%d %H:%M:%S' "$LE" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
  WE=$(date -j -v+2M -f '%Y-%m-%d %H:%M:%S' "$LE" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
fi
if [ -n "$WS" ] && [ -n "$WE" ]; then
  echo "   previous session's last kernel line: $LE  (saving $WS to $WE)"
  log show --start "$WS" --end "$WE" --style compact --info 2>&1 | gzip -c > "$OUT/all-processes-before-stop.txt.gz"
else
  echo "   skipped: no earlier macOS session found in the last $H hours"
fi
echo "5/6 current drivers and collections"
kmutil showloaded --list-only > "$OUT/loaded-now.txt" 2>&1
kmutil inspect -a x86_64 -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc > "$OUT/auxkc-contents.txt" 2>&1
ls -la /Library/KernelCollections /Library/Extensions /Library/GPUBundles /Library/StagedExtensions/Library/Extensions > "$OUT/folders.txt" 2>&1
system_profiler SPDisplaysDataType > "$OUT/displays-now.txt" 2>&1
pmset -g > "$OUT/pmset.txt" 2>&1
echo "6/6 crash and hang reports"
CU=$(stat -f %Su /dev/console 2>/dev/null); UH=$(eval echo "~$CU")
mkdir -p "$OUT/diag"
for d in /Library/Logs/DiagnosticReports "$UH/Library/Logs/DiagnosticReports"; do
  [ -d "$d" ] && find "$d" -maxdepth 2 -type f -mmin -$((H * 60)) -exec cp {} "$OUT/diag/" \; 2>/dev/null
done
sync
echo
echo "kernel.txt.gz: $(gzip -dc "$OUT/kernel.txt.gz" | wc -l | tr -d ' ') lines   reports copied: $(ls "$OUT/diag" | wc -l | tr -d ' ')"
[ -f "$OUT/all-processes-before-stop.txt.gz" ] && echo "all-processes-before-stop.txt.gz: $(gzip -dc "$OUT/all-processes-before-stop.txt.gz" | wc -l | tr -d ' ') lines (ends $LE)"
echo "Graphics drivers loaded right now:"; grep -iE 'TGL|WhateverXe|AMFI' "$OUT/loaded-now.txt"
echo "DONE. Saved: $OUT"
echo "Now shut down, boot Windows and tell Claude: check logs"
