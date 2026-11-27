#!/bin/bash
# 10-minute CPU load test. Finds a platform hang like WhateverXe issue #42. Works in every mode.
# Run it with only Terminal open:  bash /Volumes/1401/G15-GUIDE/07-cpu-test.sh
# Writes a line to reports/ every 30 seconds, so after a hard freeze we can see when it stopped.
DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR/reports"
LOG="$DIR/reports/cpu-test-$(date +%Y%m%d-%H%M%S).txt"
N=$(sysctl -n hw.logicalcpu 2>/dev/null); [ -n "$N" ] || N=12
BA=$(sysctl -n kern.bootargs 2>/dev/null)
{
  echo "CPU test start $(date)"
  sysctl hw.logicalcpu hw.physicalcpu machdep.cpu.core_count machdep.cpu.thread_count machdep.xcpm.mode 2>/dev/null
  case " $BA " in *" ctrsmt=full "*) echo "CPU topology kext: ON";; *) echo "CPU topology kext: OFF (noctr config)";; esac
  case " $BA " in *" nvfb=1 "*) echo "mode: NVIDIA (NullMoth)";; *" -wexoff "*) echo "mode: MAINTENANCE";; *" -wex-noaccel "*) echo "mode: N";; *) echo "mode: ACCELERATED (WhateverXe on)";; esac
  echo "boot-args: $BA"
} > "$LOG"; sync
echo "Starting $N load processes for 10 minutes."
echo "Do not use the laptop. Tap Caps Lock once a minute and watch its light."
PIDS=""
cleanup() { kill $PIDS 2>/dev/null; pkill -P $$ -x yes 2>/dev/null; }
trap 'cleanup; echo "stopped early $(date)" >> "$LOG"; sync; echo; echo "Stopped early."; exit 1' INT TERM HUP
for i in $(seq 1 "$N"); do yes > /dev/null & PIDS="$PIDS $!"; done
for t in $(seq 30 30 600); do
  sleep 30
  echo "alive at ${t}s $(date +%H:%M:%S) load: $(sysctl -n vm.loadavg)" >> "$LOG"; sync
  printf "\r%s of 600 seconds ..." "$t"
done
cleanup
echo "CPU test PASSED (finished normally) $(date)" >> "$LOG"; sync
echo
echo "PASSED: no freeze in 10 minutes. Log: $LOG"
