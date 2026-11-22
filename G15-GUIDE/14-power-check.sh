#!/bin/bash
# G15 power check: average battery power over 2 minutes. Changes nothing. No sudo needed.
# Purpose: compare mode D with mode A. If D really switches the RTX 3050 off, D draws less power.
# Before: at least 12 minutes after macOS started, brightness slider fully right, only Terminal
# open, Ethernet as usual, charger UNPLUGGED for 1 minute. Do not touch the laptop while it measures.
# Run:  bash /Volumes/1401/G15-GUIDE/14-power-check.sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
DIR="$(cd "$(dirname "$0")" && pwd)"
ST=$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/^{ sec = \([0-9]*\),.*/\1/p')
if [ -n "$ST" ] && [ $(( $(date +%s) - ST )) -lt 720 ]; then
  echo "STOP: macOS started less than 12 minutes ago and is still busy with start-up work."
  echo "Plug the charger back in and run this again at least 12 minutes after the start."
  exit 1
fi
case "$(pmset -g batt 2>/dev/null | head -n 1)" in
  *"Battery Power"*) ;;
  *) echo "STOP: the charger is connected. Unplug it, wait 1 minute, then run this again."; exit 1;;
esac
mkdir -p "$DIR/reports" || { echo "STOP: cannot write $DIR/reports"; exit 1; }
OUT="$DIR/reports/power-$(date +%Y%m%d-%H%M%S).txt"
case " $(sysctl -n kern.bootargs 2>/dev/null) " in *" -wexoff "*) M="MAINTENANCE";; *) M="ACCELERATED";; esac
NV=$(ioreg -l -w0 2>/dev/null | grep -c '"vendor-id" = <de100000>')
# ioreg can print a negative battery current as an unsigned 16-, 32- or 64-bit number: return its size in mA
mag() { echo "a=$1; m=a; if (a >= 2^15) { if (a < 2^16) m = 2^16 - a }; if (a >= 2^31) { if (a < 2^32) m = 2^32 - a }; if (a >= 2^63) m = 2^64 - a; m" | bc 2>/dev/null; }
{
  echo "=== G15 power check $(date) ==="
  echo "MODE: $M   NVIDIA dGPU devices visible: $NV  (mode D wants 0)"
  pmset -g batt 2>/dev/null | head -n 2
  echo "--- before: uptime/load and busiest processes (%CPU = about the last minute)"
  uptime
  ps -Ao pcpu,comm -r 2>/dev/null | head -n 6 | cut -c1-120
  echo "--- samples: seconds  voltage-mV  current-raw  current-mA  watts"
} > "$OUT"
echo "Measuring for 2 minutes. Do not touch the laptop..."
n=0; tot=0
for i in $(seq 1 24); do
  sleep 5
  B=$(ioreg -rn AppleSmartBattery -w0 2>/dev/null)
  V=$(echo "$B" | awk -F'= ' '/"Voltage" =/ { print $2; exit }' | tr -dc '0-9')
  R=$(echo "$B" | awk -F'= ' '/"InstantAmperage" =/ { print $2; exit }' | tr -dc '0-9')
  [ -n "$R" ] || R=$(echo "$B" | awk -F'= ' '/"Amperage" =/ { print $2; exit }' | tr -dc '0-9')
  if [ -n "$V" ] && [ -n "$R" ]; then
    A=$(mag "$R")
    W=$(echo "scale=2; $V * $A / 1000000" | bc 2>/dev/null)
    echo "$((i * 5))  $V  $R  $A  $W" >> "$OUT"
    if [ -n "$W" ]; then tot=$(echo "$tot + $W" | bc); n=$((n + 1)); fi
  else
    echo "$((i * 5))  no battery values" >> "$OUT"
  fi
done
{
  echo "--- after: uptime/load and busiest processes"
  uptime
  ps -Ao pcpu,comm -r 2>/dev/null | head -n 6 | cut -c1-120
  echo "--- result"
  if [ "$n" -gt 0 ]; then
    echo "Average battery power: $(echo "scale=1; $tot / $n" | bc) W over $n samples"
  else
    echo "Average battery power: not available (macOS shows no battery current here)"
  fi
} >> "$OUT"
sync
echo "Saved: $OUT"
grep -E 'MODE:|Average battery power' "$OUT"
echo "Plug the charger back in. Then continue with 01-STEPS.txt."
