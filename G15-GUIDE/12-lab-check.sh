#!/bin/bash
# G15 5520 NVIDIA-lab preparation check. READ-ONLY: changes nothing. Run WITHOUT sudo:
#   bash /Volumes/1401/G15-GUIDE/12-lab-check.sh
# Saves the free space of the macOS disk, the IDs of this macOS install and the macOS
# installers Apple offers, so Claude can plan a second macOS (the NVIDIA lab) safely.
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR/reports" || { echo "STOP: cannot write $DIR/reports"; exit 1; }
OUT="$DIR/reports/lab-check-$(date +%Y%m%d-%H%M%S).txt"
echo "Collecting (up to 1 minute)..."
{
  echo "=== G15 lab check $(date) ==="
  sw_vers
  echo; echo "--- APFS containers and volumes (diskutil apfs list)"
  diskutil apfs list 2>&1
  echo; echo "--- this macOS install (diskutil info /)"
  diskutil info / 2>&1 | grep -E 'Volume Name|Volume UUID|APFS Volume Group|Device Identifier|APFS Container|Container Total Space|Container Free Space|Sealed'
  echo; echo "--- Preboot folders (one per macOS install)"
  ls -la /System/Volumes/Preboot 2>&1
  echo; echo "--- free space"
  df -h / /System/Volumes/Data 2>&1
  echo; echo "--- full macOS installers Apple offers (list only, nothing is downloaded)"
  T=$(mktemp /tmp/g15-lab.XXXXXX)
  softwareupdate --list-full-installers > "$T" 2>&1 &
  P=$!
  ( sleep 60; kill "$P" 2>/dev/null ) &
  W=$!
  wait "$P" 2>/dev/null
  kill "$W" 2>/dev/null; wait "$W" 2>/dev/null   # reap the timer quietly (no "Terminated: 15" line)
  head -n 25 "$T"
  rm -f "$T"
} > "$OUT" 2>&1
sync
echo "Saved: $OUT"
echo
grep -E 'Capacity Not Allocated|Container Free Space|Size \(Capacity Ceiling\)' "$OUT" | head -6
echo "Then continue with 01-STEPS.txt."
