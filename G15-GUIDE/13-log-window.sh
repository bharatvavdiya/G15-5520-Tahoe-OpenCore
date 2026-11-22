#!/bin/bash
# Saves the FULL macOS log (every app and service) of one time window into reports/ on this USB.
# Changes nothing. Default window: the 21 Nov 2026 freeze in mode D (17:10 to 17:19, Mac clock).
# Run in MAINTENANCE mode:  sudo bash /Volumes/1401/G15-GUIDE/13-log-window.sh
# Another window:           sudo bash /Volumes/1401/G15-GUIDE/13-log-window.sh "2026-11-21 17:10:00" "2026-11-21 17:19:00"
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
[ "$(id -u)" = 0 ] || { echo "STOP: run it with sudo:  sudo bash \"$0\""; exit 1; }
DIR="$(cd "$(dirname "$0")" && pwd)"
S="${1:-2026-11-21 17:10:00}"
E="${2:-2026-11-21 17:19:00}"
for t in "$S" "$E"; do
  case "$t" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ [0-9][0-9]:[0-9][0-9]:[0-9][0-9]) ;;
    *) echo "STOP: write the times like \"2026-11-21 17:10:00\". Nothing was saved."; exit 1;;
  esac
done
mkdir -p "$DIR/reports" || { echo "STOP: cannot write $DIR/reports"; exit 1; }
OUT="$DIR/reports/log-window-$(date +%Y%m%d-%H%M%S).txt.gz"
echo "Saving the full log from $S to $E (1-3 minutes; do not use the laptop)..."
log show --start "$S" --end "$E" --style compact --info 2>&1 | gzip -c > "$OUT"
sync
N=$(gzip -dc "$OUT" | wc -l | tr -d ' ')
echo "Saved: $OUT  ($N lines)"
echo "First and last entries:"
gzip -dc "$OUT" | sed -n '2p' | cut -c1-120
gzip -dc "$OUT" | tail -n 1 | cut -c1-120
[ "$N" -gt 5 ] || echo "NOTE: almost nothing found. macOS may have deleted that time already; tell Claude."
echo "Then continue with 01-STEPS.txt."
