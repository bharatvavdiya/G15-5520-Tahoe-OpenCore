#!/bin/bash
# G15 5520 video check. READ-ONLY: changes nothing. Run it right after YouTube in Safari showed
# "An error occurred", WITHOUT sudo (it reads your own crash-report folder):
#   bash /Volumes/1401/G15-GUIDE/10-video-log.sh
# It saves: macOS version, the sound devices macOS sees (Safari's video player needs a sound
# output), recent WebKit / video decoder / WindowServer crash reports, and the media log lines
# of the last 10 minutes. Takes about 1 minute.
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR/reports" || { echo "STOP: cannot write $DIR/reports"; exit 1; }
OUT="$DIR/reports/video-log-$(date +%Y%m%d-%H%M%S).txt"
echo "Collecting (about 1 minute, please wait)..."
{
  echo "=== G15 video check $(date) ==="
  sw_vers
  echo; echo "--- sound devices macOS sees (want at least one with 'Default Output Device: Yes')"
  system_profiler SPAudioDataType 2>&1 | grep -v -i -E 'serial|uuid'
  echo; echo "--- crash reports of the last 24 hours (WebKit / VTDecoder / WindowServer / Safari)"
  find "$HOME/Library/Logs/DiagnosticReports" /Library/Logs/DiagnosticReports -maxdepth 2 -type f -mmin -1440 2>/dev/null \
    | grep -iE 'WebKit|VTDecoder|WindowServer|Safari' | head -20
  echo; echo "--- media log lines of the last 10 minutes"
  log show --last 10m --info --style compact --predicate 'eventMessage CONTAINS "GPUBundles" OR (process == "kernel" AND (eventMessage CONTAINS "GPU Data" OR eventMessage CONTAINS "GPURestart" OR eventMessage CONTAINS "signalHardwareError" OR eventMessage CONTAINS "waitForStamp")) OR (process == "com.apple.WebKit.GPU" AND (eventMessage CONTAINS[c] "error" OR eventMessage CONTAINS[c] "audio" OR eventMessage CONTAINS "GVA")) OR (process == "VTDecoderXPCService" AND (eventMessage CONTAINS[c] "error" OR eventMessage CONTAINS "GVA")) OR (process == "Safari" AND eventMessage CONTAINS "gpuProcessExited")' 2>&1 | tail -n 300
} > "$OUT" 2>&1
sync
echo "Saved: $OUT"
echo
echo "Sound devices with 'Default Output Device: Yes': $(grep -c 'Default Output Device: Yes' "$OUT")"
echo "Then start Windows and tell Claude: video report"
