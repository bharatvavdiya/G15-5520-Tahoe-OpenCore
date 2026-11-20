#!/bin/bash
# G15 5520 performance check. READ-ONLY: changes no setting, no NVRAM, no cache and no macOS file.
# It measures what can make macOS feel slow (for example icons that first show placeholders):
# Spotlight / icon cache work after the clean install, first-run Metal shader compiling, memory,
# disk activity, CPU power management (XCPM), thermal limits, Iris Xe GPU statistics and the
# WhateverXe GPU clock probe, display mode, NVMe disk / TRIM and icon / Spotlight log errors.
# The full check ends with battery power, powermetrics and a 10-second load on all CPU threads
# ('yes' processes). The load always ends by itself, also when you press Ctrl+C.
# Run it with only Terminal open, at least 5 minutes after login:
#   sudo bash /Volumes/1401/G15-GUIDE/09-perf-check.sh         -> full check (2-4 min, do not use the laptop)
#   sudo bash /Volumes/1401/G15-GUIDE/09-perf-check.sh quick   -> the same without battery, powermetrics and CPU load
#   sudo bash /Volumes/1401/G15-GUIDE/09-perf-check.sh watch   -> about 30 s of GPU / CPU samples while YOU open
#                                                                the app whose icons show placeholders
# Writes reports/perf-<date>-<time>.txt next to this script and prints a short summary at the end.
# Its temporary work folder (in /tmp on the internal disk, not on the USB stick) is deleted when it ends.
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
LC_ALL=C; export LC_ALL
[ "$(id -u)" = 0 ] || { echo "STOP: run it with sudo:  sudo bash \"$0\"${1:+ $1}"; exit 1; }
case "${1:-}" in
  ""|full|FULL) RUN=full;;
  quick|QUICK) RUN=quick;;
  watch|WATCH) RUN=watch;;
  *) echo "STOP: use no word, quick or watch. Nothing was changed."; exit 1;;
esac
DIR="$(cd "$(dirname "$0")" && pwd)"
[ -n "$DIR" ] || { echo "STOP: cannot find the folder of this script. Nothing was changed."; exit 1; }
STAMP=$(date +%Y%m%d-%H%M%S)
OUT="$DIR/reports/perf-$STAMP.txt"
mkdir -p "$DIR/reports" || { echo "STOP: cannot write $DIR/reports"; exit 1; }
# scratch files go to the internal disk: fewer writes to the FAT32 USB stick
W=$(mktemp -d /tmp/g15-perf.XXXXXX 2>/dev/null)
{ [ -n "$W" ] && [ -d "$W" ]; } || { echo "STOP: cannot create a temporary folder in /tmp. Nothing was changed."; exit 1; }
T0=$(date +%s)
CU=$(stat -f %Su /dev/console 2>/dev/null)
[ "$CU" = root ] && CU=""
UH=""
if [ -n "$CU" ]; then
  UH=$(dscl . -read "/Users/$CU" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
  [ -n "$UH" ] || UH="/Users/$CU"
fi
NCPU=$(sysctl -n hw.logicalcpu 2>/dev/null)
case "$NCPU" in ""|*[!0-9]*) NCPU=12;; esac
if [ "$NCPU" -lt 1 ] || [ "$NCPU" -gt 64 ]; then NCPU=12; fi
SPRE='^(mds|mds_stores|mdworker|mdworker_shared|mdsync|mdbulkimport|corespotlightd)$'
ICRE='^(iconservicesagent|iconservicesd)$'
WSRE='^WindowServer$'
MTRE='^MTLCompilerService$'
QLRE='^(com[.]apple[.]quicklook[.]ThumbnailsAgent|QuickLookUIService|quicklookd)$'
PSKEYS='Device Utilization %|Device Utilization % at cur p-state|Device Unit [0-9]+ Utilization %|recoveryCount|inUseSysMemoryBytes|inUseVidMemoryBytes|gartUsedBytes|gartSizeBytes|textureCount|surfaceCount|context2DCount|contextGLCount|contextCLCount|contextVideoCount|hardwareWaitTime|hardwareSubmitWaitTime|finishGLWaitTime|vramEvictionWaitTime|freeToAllocGPUAddressWaitTime|texturePageOutBytes|stdTexturePageInBytes|ioSurfacePageInBytes|ioSurfacePageOutBytes|textureVolunteerUnloadBytes'
APRED='process == "kernel" AND (eventMessage CONTAINS[c] "trim" OR eventMessage CONTAINS[c] "spaceman" OR eventMessage CONTAINS[c] "nvme")'
IPRED='(process == "iconservicesagent" OR process == "iconservicesd" OR process BEGINSWITH "mds" OR process BEGINSWITH "mdworker" OR process == "corespotlightd" OR process == "lsd") AND (messageType == error OR messageType == fault)'
WPRED='(process == "kernel" AND (eventMessage CONTAINS "Sandbox: MTLCompilerService(" OR eventMessage CONTAINS "GPURestart" OR eventMessage CONTAINS "Appears hung" OR eventMessage CONTAINS "checkGPUProgress" OR eventMessage CONTAINS "reloading after unclean unmount" OR (eventMessage CONTAINS "Sandbox: com.apple.WebKit.GPU" AND eventMessage CONTAINS "GPUBundles"))) OR ((messageType == error OR messageType == fault) AND ((process == "WindowServer" AND eventMessage CONTAINS "timed out") OR eventMessage CONTAINS "fopen failed for data file"))'
WEXKEYS='N97HostRPSRequested|N97HostRPSReady|TGLHostRPSReady|N97FramebufferStartAccepted|WhateverXeDataAccess|WhateverXeDataAccessSymbols|WhateverXeWebKitIdentitySymbols|TGLRenderWakeLifetimeTrial'
HDR='^(Machine model|SMC version|EFI version|OS version|Boot arguments|Boot time):'
BPID=""; LOADPIDS=""; LWD=""; BOOTSEC=""; UPS="?"; PMS=cpu_power
PS_NS=""; PS_RC6=""; PS_CALLS=""; PS_MHZ="?"; PS_PCT="?"
exec 3>&1

# ---------------------------------------------------------------- helpers
step() { echo "$*" >&3; sync; }
have() { command -v "$1" >/dev/null 2>&1; }
# print stdin, or the text in $1 when stdin is empty
orsay() { _o=$(cat); if [ -n "$_o" ]; then printf '%s\n' "$_o"; else printf '%s\n' "$1"; fi; }
# join lines into one line, separated by "; "
oneline() { sed 's/^[[:space:]]*//' | tr -s ' \t' ' ' | tr '\n' ';' | sed 's/;$//; s/;/; /g'; }
# bounded SECONDS command [args]: macOS has no 'timeout' command, so the command runs in the
# background and is stopped (with its child processes) when it is still running after SECONDS.
bounded() {
  _max=$1; shift
  "$@" 2>&1 3>&- &
  BPID=$!
  _end=$((SECONDS + _max))
  while kill -0 "$BPID" 2>/dev/null; do
    if [ "$SECONDS" -ge "$_end" ]; then
      pkill -P "$BPID" 2>/dev/null
      kill "$BPID" 2>/dev/null
      _k=0
      while kill -0 "$BPID" 2>/dev/null && [ "$_k" -lt 10 ]; do sleep 0.2; _k=$((_k + 1)); done
      kill -9 "$BPID" 2>/dev/null
      echo "(stopped after $_max seconds; the output above may be incomplete)"
      break
    fi
    sleep 0.2
  done
  wait "$BPID" 2>/dev/null
  BPID=""
  return 0
}
# system_profiler without serial numbers or UUIDs (they never reach the report or the work folder)
sp() {
  bounded 40 system_profiler "$1" > "$W/sp-raw.txt"
  grep -v -i -E 'serial|uuid' "$W/sp-raw.txt"
  rm -f "$W/sp-raw.txt"
}
# CPU load: one 'yes' per CPU thread, plus a safety timer that ends it after 15 s whatever happens
start_load() {
  _i=0
  while [ "$_i" -lt "$NCPU" ]; do
    yes > /dev/null 2>&1 3>&- &
    LOADPIDS="$LOADPIDS $!"
    _i=$((_i + 1))
  done
  ( sleep 15; kill $LOADPIDS ) < /dev/null > /dev/null 2>&1 3>&- &
  LWD=$!
}
stop_load() {
  if [ -n "$LOADPIDS" ]; then kill $LOADPIDS 2>/dev/null; wait $LOADPIDS 2>/dev/null; fi
  pkill -P $$ -x yes 2>/dev/null
  if [ -n "$LWD" ]; then kill "$LWD" 2>/dev/null; wait "$LWD" 2>/dev/null; fi
  LOADPIDS=""; LWD=""
}
cleanup() {
  if [ -n "$BPID" ]; then pkill -P "$BPID" 2>/dev/null; kill "$BPID" 2>/dev/null; fi
  BPID=""
  stop_load
  if [ -n "$W" ] && [ -d "$W" ]; then rm -rf "$W"; fi
}
trap cleanup EXIT
trap 'cleanup; echo >&3; echo "Stopped early. The CPU load (if it was running) is stopped. Partial report: $OUT" >&3; exit 1' INT TERM HUP

# ---------------------------------------------------------------- readers (each prints one result)
bootsec() { sysctl -n kern.boottime 2>/dev/null | sed -n 's/^{ sec = \([0-9]*\),.*/\1/p'; }
prevented() { grep -o 'prevented by [^)]*' "$1" 2>/dev/null | head -n 1; }
# mdutil -s output as one line: "volume: status; volume: status"
volstat() { awk '/:$/ { v = $0; next } NF { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); printf "%s%s %s", (n++ ? "; " : ""), v, $0 }' "$1"; }
memfree() { sed -n 's/.*free percentage: *\([0-9]*\).*/\1/p' "$1" | head -n 1; }
swapused() { sysctl -n vm.swapusage 2>/dev/null | sed -n 's/.*used = \([^ ]*\).*/\1/p'; }
vmcount() { awk -F: -v k="$1" '$1 == k { gsub(/[ .]/, "", $2); print $2 }' "$2"; }
topsum() {
  grep '^ *PID' "$1" | head -n 1
  awk 'h && NF { print; c++ } /^ *PID/ { h = 1 } c >= 5 { exit }' "$1"
}
# the PerformanceStatistics dictionary of the GPU, one key=value per line
psdump() { sed -n 's/.*"PerformanceStatistics" = {\(.*\)}.*$/\1/p' "$1" | tr ',' '\n'; }
psval() { psdump "$2" | grep -F "\"$1\"=" | head -n 1 | sed 's/.*=//'; }
# powermetrics cpu_power: average package power, CPU clock, GPU active and the reported limit reasons
pmsum() {
  awk '
    /package power/ { v = $NF; gsub(/[^0-9.]/, "", v); if (v != "") { pw += v; np++ } }
    /^System Average frequency/ {
      if (match($0, /\([0-9.]+ *[MmGg][Hh][Zz]\)/)) {
        s = substr($0, RSTART + 1, RLENGTH - 2); f = s + 0
        if (s ~ /[Gg][Hh][Zz]/) f = f * 1000
        fq += f; nf++
      }
    }
    /^GPU Active:/ { v = $3; gsub(/[^0-9.]/, "", v); if (v != "") { ga += v; ng++ } }
    /^(CPU|GPU) LIMIT/ { lim[$0] = 1 }
    END {
      o = "package " (np ? sprintf("%.1f W", pw / np) : "n/a")
      o = o " | avg CPU clock " (nf ? sprintf("%.0f MHz", fq / nf) : "n/a")
      o = o " | GPU active " (ng ? sprintf("%.1f%%", ga / ng) : "n/a")
      l = ""
      for (k in lim) l = l (l == "" ? "" : ", ") k
      o = o " | limited by: " (l == "" ? "nothing reported" : l)
      print o
    }' "$1"
}
# powermetrics cpu_power: highest clock seen on the P-cores (CPU 0-3 on this laptop) and E-cores (CPU 4-11)
coremax() {
  awk '
    /^CPU [0-9]+ duty cycles/ { c = $2 + 0; h = 1; next }
    /^CPU Average frequency as fraction of nominal/ {
      if (h && match($0, /\([0-9.]+ *[Mm][Hh][Zz]\)/)) {
        f = substr($0, RSTART + 1, RLENGTH - 2) + 0
        if (c < 4) { if (f > pm) pm = f; pn++ } else { if (f > em) em = f; en++ }
      }
      h = 0
    }
    END { printf "P-cores (CPU 0-3) max %s | E-cores (CPU 4-11) max %s", (pn ? sprintf("%.0f MHz", pm) : "n/a"), (en ? sprintf("%.0f MHz", em) : "n/a") }' "$1"
}
sensors() { grep -E 'die temperature|Fan:|Thermal level|pressure level' "$1" 2>/dev/null | oneline; }
thermnow() { grep -E 'Level|Limit|No ' "$1" 2>/dev/null | sed -e 's/Note: //' -e 's/ has been recorded//' | oneline; }
# CPU time used by every process since it started: "seconds pid %cpu name", busiest first
cpusince() {
  ps -Ao pid=,pcpu=,time=,comm= 2>/dev/null | awk '
    function secs(t,   a, n, d, p) {
      d = 0; p = index(t, "-")
      if (p > 0) { d = substr(t, 1, p - 1) + 0; t = substr(t, p + 1) }
      n = split(t, a, ":")
      if (n == 3) return d * 86400 + a[1] * 3600 + a[2] * 60 + a[3]
      if (n == 2) return d * 86400 + a[1] * 60 + a[2]
      return d * 86400 + a[1]
    }
    NF >= 4 {
      c = $0
      sub(/^[ \t]*[0-9]+[ \t]+[0-9.]+[ \t]+[-0-9:.]+[ \t]+/, "", c)
      n = c; sub(/.*\//, "", n); sub(/^[(]/, "", n); sub(/[)]$/, "", n)
      printf "%.2f %s %s %s\n", secs($3), $1, $2, n
    }' | sort -rn
}
# CPU seconds used between two cpusince lists (same format), busiest first
cpudelta() {
  awk 'NR == FNR { s[$2] = $1; next }
       { d = $1; if ($2 in s) d = $1 - s[$2]; if (d < 0) d = $1
         n = $4; for (i = 5; i <= NF; i++) n = n " " $i
         printf "%.2f %s %s %s\n", d, $2, $3, n }' "$1" "$2" | sort -rn
}
# total CPU seconds of the processes whose full name matches the regular expression $2
famsum() { awk -v re="$2" '{ n = $4; for (i = 5; i <= NF; i++) n = n " " $i } n ~ re { s += $1; k++ } END { printf "%.1f s (%d processes)", s, k }' "$1"; }
busiest() { head -n "$2" "$1" | awk '{ n = $4; for (i = 5; i <= NF; i++) n = n " " $i; printf "%s%s %.1f", (NR > 1 ? ", " : ""), n, $1 }'; }
cputable() { head -n "$2" "$1" | awk '{ n = $4; for (i = 5; i <= NF; i++) n = n " " $i; printf "%9.2f %7s %5s  %s\n", $1, $2, $3, n }'; }
birth() {
  case "$1" in /*) ;; *) echo "-"; return;; esac
  if [ -e "$1" ]; then stat -f '%SB' -t '%Y-%m-%d %H:%M' "$1" 2>/dev/null; else echo "-"; fi
}
stamps() { stat -f 'created %SB  modified %Sm' -t '%Y-%m-%d %H:%M' "$1" 2>&1; }
kbsize() { awk '$1 ~ /^[0-9]+$/ { k = $1 } END { if (k == "") k = "?"; print k }' "$1"; }
pick() { grep -E "$1" "$2" 2>/dev/null | oneline; }
# the 'trims took' lines; the short '(no trims)' scan logged first at every start is normal
trimsum() {
  _t=$(grep 'trims took' "$1" 2>/dev/null | head -n 2)
  [ -n "$_t" ] || _t=$(grep -i 'trim' "$1" 2>/dev/null | grep -v -E '^(Timestamp|Filtering)' | head -n 2)
  printf '%s\n' "$_t" | sed 's/^[^ ]* *[^ ]* *[^ ]* *[^ ]* *//' | cut -c1-150 | oneline
}
# log lines in compact style: count per process, and the most frequent messages (numbers as #)
errcount() {
  awk '$1 ~ /^[0-9][0-9][0-9][0-9]-/ && $4 ~ /\[[0-9]+:/ { p = $4; sub(/\[.*/, "", p); c[p]++ }
       END { for (k in c) print c[k], k }' "$1" | sort -rn
}
errtop() {
  awk '$1 ~ /^[0-9][0-9][0-9][0-9]-/ && $4 ~ /\[[0-9]+:/ {
         p = $4; sub(/\[.*/, "", p); m = $0
         sub(/^[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ */, "", m)
         gsub(/0x[0-9a-fA-F]+/, "#", m); gsub(/[0-9]+/, "#", m)
         print p ": " substr(m, 1, 140) }' "$1" | sort | uniq -c | sort -rn | head -n 12
}
errsum() { head -n 5 "$1" | awk '{ printf "%s%s %s", (NR > 1 ? ", " : ""), $2, $1 } END { if (NR == 0) printf "none" }'; }
# kernel APFS TRIM / NVMe lines: same start as 'log show --last boot', but only the first 15 minutes
# (TRIM runs when the disk is mounted at start), which keeps it fast
boot_log() {
  _ls=""; _le=""
  if [ -n "$BOOTSEC" ]; then
    _ls=$(date -r "$BOOTSEC" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    if [ "$UPS" != "?" ] && [ "$UPS" -gt 960 ]; then
      _le=$(date -r $((BOOTSEC + 900)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    fi
  fi
  if [ -n "$_ls" ] && [ -n "$_le" ]; then
    bounded 30 log show --style compact --start "$_ls" --end "$_le" --predicate "$APRED"
  elif [ -n "$_ls" ]; then
    bounded 30 log show --style compact --start "$_ls" --predicate "$APRED"
  else
    bounded 30 log show --style compact --last boot --predicate "$APRED"
  fi
}
diaglist() {
  for _d in /Library/Logs/DiagnosticReports "${UH:+$UH/Library/Logs/DiagnosticReports}"; do
    [ -n "$_d" ] && [ -d "$_d" ] && find "$_d" -maxdepth 2 -type f -mmin -1440 2>/dev/null
  done | sed 's#.*/##' | sort
}
diagsum() {
  printf '%s files | mds* crashes %s | cpu_resource %s | WindowServer %s' \
    "$(wc -l < "$1" | tr -d ' ')" "$(grep -c '^mds' "$1")" "$(grep -c 'cpu_resource' "$1")" "$(grep -c '^WindowServer' "$1")"
}
# user names in network-share mount lines are replaced by <user>
masku() { sed -E 's#//[^/@ ]+@#//<user>@#g; s/mounted by [^,)]+/mounted by <user>/g'; }
# seconds since this start for a log time "YYYY-MM-DD HH:MM:SS", or ? when the clock looks wrong
upofs() {
  _e=$(date -j -f '%Y-%m-%d %H:%M:%S' "$1" '+%s' 2>/dev/null)
  case "$_e" in ""|*[!0-9]*) echo "?"; return;; esac
  case "$BOOTSEC" in ""|*[!0-9]*) echo "?"; return;; esac
  _u=$((_e - BOOTSEC))
  _n=$(( $(date +%s) - BOOTSEC + 60 ))
  if [ "$_u" -lt 0 ] || [ "$_u" -gt "$_n" ]; then echo "?"; else echo "$_u"; fi
}
# how many values in the first column are at most 2, 5, 7 and 20 minutes (seconds since start)
bycount() { awk '$1 ~ /^[0-9]+$/ { if ($1 <= 120) a++; if ($1 <= 300) b++; if ($1 <= 420) c++; if ($1 <= 1200) d++ } END { printf "%d / %d / %d / %d", a, b, c, d }' "$1"; }
# battery voltage, current and power now (one line; negative W = running on the battery)
battery() {
  ioreg -r -n AppleSmartBattery -w0 2>/dev/null | awk -v t="$(date +%H:%M:%S)" '
    function sval(v,  d) { if (length(v) > 15) { d = substr(v, length(v) - 9) + 0; return -((3709551616 - d + 10000000000) % 10000000000) } return v + 0 }
    /"Voltage" = / { split($0, a, "= "); mv = a[2] + 0 }
    /"Amperage" = / { split($0, a, "= "); am = sval(a[2]) }
    /"ExternalConnected" = / { split($0, a, "= "); ac = a[2] }
    END { if (mv) print t "  AC=" ac "  V=" sprintf("%.2f", mv / 1000) "  I=" am " mA  P=" sprintf("%.1f", mv * am / 1000000) " W" }'
}
batsum() {
  awk '{ for (i = 1; i <= NF; i++) { if ($i ~ /^P=/) { s += substr($i, 3) + 0; n++ } if ($i ~ /^AC=/) ac = substr($i, 4) } }
       END { if (n) printf "average %.1f W over %d samples (AC=%s; negative = from the battery)", s / n, n, ac; else printf "no battery data" }' "$1"
}
# WhateverXe 0.8.3 live GPU probe (official diagnostic property N97GTPowerSample on Alder Lake,
# TGLPowerSample on Tiger Lake). It reads always-on registers only. WhateverXe answers 512 reads per
# boot; one sample uses about 2 and every full 'ioreg -l' 1, so this script uses about 5 (quick/full)
# or 10 (watch). Decoding: GPU clock = RPSTAT1 bits 19:11 x 50/3 MHz, RC6 counter in 1.28 us ticks.
le64() { local h=$1 o="" i; for i in 14 12 10 8 6 4 2 0; do o="$o${h:$i:2}"; done; printf '%d' "0x$o"; }
psample() {
  local label=$1 key hex i cagf mhz lastmhz rp0 rpn rc6txt callstxt drc6 dns pct
  local -a v
  PS_MHZ="?"; PS_PCT="?"; hex=""
  for key in N97GTPowerSample TGLPowerSample; do
    hex=$(ioreg -lw0 -r -k "$key" -d1 2>/dev/null | sed -n "s/.*\"$key\" = <\([0-9a-fA-F]*\)>.*/\1/p" | head -n 1)
    [ ${#hex} -ge 256 ] && break
  done
  if [ ${#hex} -lt 256 ]; then echo "$label  GPU probe not found (N97GTPowerSample / TGLPowerSample missing)"; return; fi
  for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do v[$i]=$(le64 "${hex:$((i * 16)):16}"); done
  if [ "${v[1]}" != 1 ]; then
    if [ "${v[11]}" -ge 512 ]; then echo "$label  GPU probe gave no register data: read #${v[11]}, the 512-per-boot limit is used up"
    else echo "$label  GPU probe gave no register data (read #${v[11]}): WhateverXe's own safety checks were not met"; fi
    return
  fi
  cagf=$(( (v[3] >> 11) & 511 ))
  mhz=$(( cagf * 50 / 3 ))
  lastmhz=$(( (v[14] >> 23) * 50 / 3 ))
  rp0=$(( (v[15] & 255) * 50 )); rpn=$(( ((v[15] >> 16) & 255) * 50 ))
  rc6txt="n/a (first sample)"; callstxt=""
  if [ -n "$PS_NS" ] && [ "${v[2]}" -gt "$PS_NS" ]; then
    drc6=$(( (v[4] - PS_RC6) & 4294967295 )); dns=$(( v[2] - PS_NS ))
    pct=$(( drc6 * 1280 * 100 / dns ))
    if [ "$pct" -le 100 ]; then rc6txt="${pct}%"; PS_PCT=$pct; else rc6txt="n/a (raw +$drc6 ticks in $(( dns / 1000000 )) ms: counter units differ)"; fi
    callstxt=" (+$(( v[12] - PS_CALLS )) since previous sample)"
  fi
  PS_NS=${v[2]}; PS_RC6=${v[4]}; PS_CALLS=${v[12]}; PS_MHZ=$mhz
  echo "$label  GPU clock now ${mhz} MHz | RC6 (GPU asleep) since previous sample: $rc6txt | macOS request $(( v[7] * 50 )) MHz boost $(( v[8] * 50 )) MHz | last host-RPS answer ${lastmhz} MHz | host-RPS calls ${v[12]}$callstxt answered ${v[13]} | hardware limits min ${rpn} / max ${rp0} MHz | probe read #${v[11]} (schema ${v[0]})"
}

# ---------------------------------------------------------------- collection
if [ "$RUN" = watch ]; then
  echo "G15 performance check (watch): about 40 seconds. Follow the lines below."
elif [ "$RUN" = quick ]; then
  echo "G15 performance check (quick): 1 to 3 minutes. Please do not use the laptop meanwhile."
else
  echo "G15 performance check (full): 2 to 4 minutes. Please do not use the laptop meanwhile."
fi
{
  echo "=== G15 performance check ($RUN) $(date) ==="
  echo "Read-only check. Report: $OUT"
  BA=$(sysctl -n kern.bootargs 2>/dev/null)
  [ -n "$BA" ] || BA=$(nvram boot-args 2>/dev/null | cut -f2-)
  SAFE=$(sysctl -n kern.safeboot 2>/dev/null)
  case " $BA " in
    *" -wexoff "*) MODE="MAINTENANCE (WhateverXe off)";;
    *" -wex-noaccel "*) MODE="N (WhateverXe display only)";;
    *) MODE="ACCELERATED (WhateverXe on)";;
  esac
  [ "$SAFE" = 1 ] && MODE="$MODE + SAFE MODE (slow by design)"
  echo "## MODE: $MODE"
  echo "## uptime: $(uptime 2>/dev/null | sed 's/^ *//')"
  BOOTSEC=$(bootsec)
  if [ -n "$BOOTSEC" ]; then UPS=$(( $(date +%s) - BOOTSEC )); fi
  echo "seconds since start: $UPS"

  if [ "$RUN" = watch ]; then
    # ------------------------------------------------ watch: measure while the placeholders appear
    step "Get ready: in about 5 seconds, open the app whose icons show placeholders (for example System Settings)."
    psample "before     " > "$W/probe.txt"
    PS0=$PS_MHZ
    sleep 4
    cpusince > "$W/w0.txt"
    step "NOW: open the app and click 3 or 4 items. Keep going until this window says Saved (about 30 s)."
    T1=$SECONDS
    GL=""; PCL=""; RCL=""
    i=1
    while [ "$i" -le 20 ]; do
      ioreg -r -c IOAccelerator -d 1 -l -w0 > "$W/wacc.txt" 2>&1 || true
      g=$(psval 'Device Utilization %' "$W/wacc.txt")
      GL="$GL ${g:-?}"
      case "$i" in
        5|10|15|20) psample "ui t+$((SECONDS - T1))s" >> "$W/probe.txt"; PCL="$PCL $PS_MHZ"; RCL="$RCL $PS_PCT";;
      esac
      sleep 1
      i=$((i + 1))
    done
    cpusince > "$W/w1.txt"
    WT=$((SECONDS - T1))
    cpudelta "$W/w0.txt" "$W/w1.txt" > "$W/wd.txt"
    GMAX=$(echo "$GL" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -rn | head -n 1)
    echo; echo "--- watch window: $WT s"
    echo "WhateverXe GPU probe (GPU clock; RC6 = share of time the GPU slept since the previous sample):"
    cat "$W/probe.txt"
    echo "GPU Device Utilization %, about once per second (may stay 0 under WhateverXe even when busy):$GL"
    echo; echo "--- CPU seconds used during the window (busiest 20)"
    echo "    CPU-s     PID  %CPU  process"
    cputable "$W/wd.txt" 20
    echo "## watch ($WT s) GPU probe: clock before ${PS0} MHz, while clicking (about every 5 s):$PCL MHz | RC6 (GPU asleep) per 5 s:$RCL %"
    echo "## watch GPU Device Utilization max ${GMAX:-?}% (may read 0 under WhateverXe) | per second:$GL"
    echo "## watch CPU seconds in the window: $(busiest "$W/wd.txt" 8)"
    echo "## watch groups: icons $(famsum "$W/wd.txt" "$ICRE") | WindowServer $(famsum "$W/wd.txt" "$WSRE") | Spotlight $(famsum "$W/wd.txt" "$SPRE") | Metal compiler $(famsum "$W/wd.txt" "$MTRE") | QuickLook $(famsum "$W/wd.txt" "$QLRE")"
  else
    step "1/9 system and memory"
    echo; echo "--- macOS version"; sw_vers 2>&1 || true
    echo; echo "--- uptime / load"; uptime 2>&1 || true
    echo; echo "--- boot-args of this start (kern.bootargs), then NVRAM"
    printf '%s\n' "$BA"
    nvram boot-args 2>&1 || true
    echo "kern.safeboot: ${SAFE:-?}"
    echo; echo "--- memory"
    sysctl hw.memsize 2>&1 || true
    sysctl vm.swapusage 2>&1 || true
    MEMB=$(sysctl -n hw.memsize 2>/dev/null)
    MEMGB="?"
    case "$MEMB" in ""|*[!0-9]*) ;; *) MEMGB=$((MEMB / 1073741824));; esac
    echo; echo "--- memory_pressure -Q"
    if have memory_pressure; then bounded 10 memory_pressure -Q > "$W/mp.txt"; else echo "(memory_pressure not found)" > "$W/mp.txt"; fi
    cat "$W/mp.txt"
    echo; echo "--- vm_stat"
    vm_stat > "$W/vm.txt" 2>&1 || true
    cat "$W/vm.txt"
    echo "## memory: $MEMGB GB RAM | free $(memfree "$W/mp.txt")% | swap used $(swapused) | pageouts $(vmcount Pageouts "$W/vm.txt") | swapouts $(vmcount Swapouts "$W/vm.txt")"

    step "2/9 what uses the CPU and the disk (top, iostat, Spotlight, mounted disks, busiest processes)"
    echo; echo "--- top 15 processes by CPU (2nd of 2 samples 3 s apart; the 1st sample has no valid %CPU)"
    bounded 20 top -l 2 -s 3 -o cpu -n 15 -stats pid,command,cpu,mem,threads,state,time,user > "$W/top.txt"
    grep -q '^ *PID' "$W/top.txt" || bounded 20 top -l 2 -s 3 -o cpu -n 15 > "$W/top.txt"
    awk '/^Processes:/ { n++ } n >= 2' "$W/top.txt" > "$W/top2.txt"
    [ -s "$W/top2.txt" ] || cp "$W/top.txt" "$W/top2.txt"
    cat "$W/top2.txt"
    echo "## CPU now: $(grep '^CPU usage' "$W/top2.txt" | head -n 1)"
    topsum "$W/top2.txt" | sed 's/^/## top: /'
    echo; echo "--- disk activity (iostat -d -c 4 -w 1: KB per transfer, transfers/s, MB/s; the 1st line is the average since start)"
    if have iostat; then bounded 10 iostat -d -c 4 -w 1 > "$W/iostat.txt"; else echo "(iostat not found)" > "$W/iostat.txt"; fi
    cat "$W/iostat.txt"
    echo "## disk now (iostat, last second): $(sed -n '1p' "$W/iostat.txt" | tr -s ' ' | sed 's/^ //') | $(tail -n 1 "$W/iostat.txt" | tr -s ' ' | sed 's/^ //')"
    echo; echo "--- Spotlight status of all volumes (mdutil -s -a: only says whether indexing is on, not how far it is)"
    if have mdutil; then
      bounded 15 mdutil -s -a > "$W/mdutil.txt"
      if ! grep -q -i 'index' "$W/mdutil.txt"; then
        bounded 15 mdutil -s / >> "$W/mdutil.txt"
        bounded 15 mdutil -s /System/Volumes/Data >> "$W/mdutil.txt"
      fi
    else
      echo "(mdutil not found)" > "$W/mdutil.txt"
    fi
    cat "$W/mdutil.txt"
    SPOT=$(volstat "$W/mdutil.txt")
    USBVOL="$(cd "$DIR/.." && pwd)"
    USBIDX="?"
    if [ -n "$USBVOL" ] && [ "$USBVOL" != / ]; then
      bounded 15 mdutil -s "$USBVOL" > "$W/mdusb.txt"
      if grep -q -i 'indexing enabled' "$W/mdusb.txt"; then USBIDX=yes; elif grep -q -i 'disabled' "$W/mdusb.txt"; then USBIDX=no; fi
    fi
    echo "Spotlight indexing of this USB stick ($USBVOL), from mdutil -s: $USBIDX"
    echo; echo "--- mounted file systems (smbfs = a network share; user names replaced by <user>)"
    mount 2>/dev/null | masku > "$W/mount.txt"
    orsay "(mount gave no output)" < "$W/mount.txt"
    NSMB=$(grep -c '(smbfs' "$W/mount.txt")
    echo; echo "--- indexing processes running (pgrep -lf 'mds|mdworker')"
    pgrep -lf 'mds|mdworker' 2>&1 | cut -c1-220 | orsay "(none)"
    NIDX=$(pgrep -f 'mds|mdworker' 2>/dev/null | wc -l | tr -d ' ')
    echo; echo "--- power assertions by process (mds here = Spotlight is working)"
    bounded 10 pmset -g assertions > "$W/assert.txt"
    sed -n '/Listed by owning process/,/Kernel Assertions/p' "$W/assert.txt" | head -n 40 | orsay "$(head -n 40 "$W/assert.txt")"
    bounded 10 pmset -g > "$W/pmsetg.txt"
    PREV=$(prevented "$W/pmsetg.txt")
    echo "pmset: ${PREV:-nothing prevents sleep}"
    echo; echo "--- CPU time used since each process started (busiest 20; this start was $UPS s ago)"
    cpusince > "$W/since.txt"
    echo "    CPU-s     PID  %CPU  process"
    cputable "$W/since.txt" 20
    echo "## busiest since start (CPU seconds; start was $UPS s ago): $(busiest "$W/since.txt" 6)"
    echo "## Spotlight: indexing processes now: $NIDX | mds* CPU $(famsum "$W/since.txt" "$SPRE") | iconservices CPU $(famsum "$W/since.txt" "$ICRE") | ${PREV:-sleep not held by mds} | USB stick indexed: $USBIDX"
    echo "## Spotlight volumes: ${SPOT:-?} | network shares mounted (smbfs): $NSMB"
    echo "## other CPU since start: WindowServer $(famsum "$W/since.txt" "$WSRE") | Metal shader compiler $(famsum "$W/since.txt" "$MTRE") | QuickLook thumbnails $(famsum "$W/since.txt" "$QLRE")"

    step "3/9 CPU power management (XCPM) and thermal limits"
    echo; echo "--- CPU"
    for k in machdep.cpu.brand_string hw.physicalcpu hw.logicalcpu hw.cpufrequency hw.cpufrequency_max hw.cpufrequency_min hw.busfrequency hw.tbfrequency machdep.tsc.frequency; do
      v=$(sysctl -n "$k" 2>/dev/null)
      if [ -n "$v" ]; then echo "$k: $v"; else echo "$k: (not present)"; fi
    done
    echo; echo "--- sysctl machdep.xcpm (all)"
    sysctl machdep.xcpm > "$W/xcpm.txt" 2>&1 || true
    cat "$W/xcpm.txt"
    XPP=$(ioreg -r -c X86PlatformPlugin -d 1 -w0 2>/dev/null | grep -c 'X86PlatformPlugin  <class')
    echo "X86PlatformPlugin objects (Apple CPU power management plugin, want 1): $XPP"
    XMODE=$(sed -n 's/^machdep.xcpm.mode: //p' "$W/xcpm.txt")
    XTH=$(grep 'thermal_level' "$W/xcpm.txt" | sed 's/^machdep.xcpm.//' | oneline)
    XPL=$(grep 'plimit' "$W/xcpm.txt" | grep 'max' | sed 's/^machdep.xcpm.//' | oneline)
    echo "## CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null) | $NCPU threads | XCPM mode ${XMODE:-?} | X86PlatformPlugin $XPP | ${XTH:-no thermal_level keys}${XPL:+ | $XPL}"
    echo; echo "--- pmset -g therm (CPU_Speed_Limit below 100 = the CPU is slowed down for heat or power)"
    bounded 10 pmset -g therm > "$W/therm.txt"
    cat "$W/therm.txt"
    echo "## thermal now (pmset -g therm): $(thermnow "$W/therm.txt")"
    echo; echo "--- Low Power Mode per power source (pmset -g custom; want 0 for Battery Power and AC Power)"
    bounded 10 pmset -g custom > "$W/custom.txt"
    grep -E 'Power:|lowpowermode|powermode' "$W/custom.txt" | orsay "(no lowpowermode lines)"
    LPM=$(awk '/Power:/ { s = $1 } $1 == "lowpowermode" || $1 == "powermode" { printf "%s%s %s %s", (n++ ? " | " : ""), s, $1, $2 }' "$W/custom.txt")
    echo "## Low Power Mode (want 0): ${LPM:-not reported}"

    step "4/9 Iris Xe GPU statistics and the WhateverXe GPU probe"
    echo; echo "--- GPU (IOAccelerator) PerformanceStatistics: 3 samples, 1 s apart"
    for s in 1 2 3; do
      ioreg -r -c IOAccelerator -d 1 -l -w0 > "$W/acc$s.txt" 2>&1 || true
      echo "sample $s at $(date +%H:%M:%S):"
      grep -E '^[+]-o ' "$W/acc$s.txt" | cut -c1-160
      psdump "$W/acc$s.txt" | grep -E "^\"($PSKEYS)\"=" | sed 's/^/    /'
      [ "$s" = 3 ] || sleep 1
    done
    echo; echo "--- GPU driver facts"
    grep -E '"(VRAM,totalMB|MetalPluginName|AGCInfo|Development)" =' "$W/acc1.txt" | sed 's/^[[:space:]|]*//' | cut -c1-1500
    GM=$(psval inUseSysMemoryBytes "$W/acc3.txt")
    GMM="?"
    case "$GM" in ""|*[!0-9]*) ;; *) GMM=$((GM / 1048576));; esac
    echo "## GPU idle: utilization $(psval 'Device Utilization %' "$W/acc3.txt")% | recoveryCount $(psval recoveryCount "$W/acc3.txt") (above 0 = the driver had to recover the GPU) | in-use memory $GMM MB"
    echo; echo "--- WhateverXe status on the IORegistry root (want = Yes on each line; TGLRenderWakeLifetimeTrial must be absent)"
    ioreg -lw0 -d1 2>/dev/null | grep -E "\"($WEXKEYS)\" =" | sed 's/^[ |]*//' > "$W/wex.txt"
    orsay "(none of these WhateverXe properties found)" < "$W/wex.txt"
    WEXS=$(sed 's/"//g; s/ = /=/' "$W/wex.txt" | oneline)
    echo; echo "--- WhateverXe GPU probe at idle: 2 samples 5 s apart (RC6 = share of time the GPU slept; 0 MHz = asleep at that moment)"
    psample "idle t+0s"
    IDC=$PS_MHZ
    sleep 5
    psample "idle t+5s"
    echo "## WhateverXe: ${WEXS:-status properties not found}"
    echo "## GPU probe at idle: clock $IDC / $PS_MHZ MHz (0 / 5 s) | RC6 (GPU asleep) over 5 s: ${PS_PCT}% (the watch run shows the same while you click)"

    step "5/9 display, NVIDIA, NVMe disk"
    echo; echo "--- display mode (system_profiler SPDisplaysDataType)"
    sp SPDisplaysDataType > "$W/disp.txt"
    grep -E 'Chipset Model|Metal|VRAM|Resolution|UI Looks like|Framebuffer Depth|Device ID|Kernel Extension Info|Connection Type|stopped after' "$W/disp.txt" | sed 's/^[[:space:]]*//' | orsay "(no display information)"
    echo "## display: $(pick 'Metal Support|VRAM|UI Looks like' "$W/disp.txt")"
    echo; echo "--- NVIDIA dGPU seen by macOS (mode D turns it off: want 0 there)"
    NV=$(ioreg -l -w0 2>/dev/null | grep -c '"vendor-id" = <de100000>')
    echo "NVIDIA dGPU devices visible: $NV"
    echo "## NVIDIA dGPU devices visible: $NV (0 = switched off in macOS, as in mode D)"
    echo; echo "--- NVMe disk (system_profiler SPNVMeDataType: model, firmware, TRIM, PCIe link)"
    sp SPNVMeDataType > "$W/nvme.txt"
    grep -E '^[[:space:]]*(Model|Revision|TRIM Support|Link Width|Link Speed|S\.M\.A\.R\.T\. status|Detachable Drive):|^[[:space:]]*BSD Name: disk[0-9]+$|stopped after' "$W/nvme.txt" | sed 's/^[[:space:]]*//' | orsay "(no NVMe information)"
    echo "## NVMe: $(pick '^[[:space:]]*(Model|TRIM Support|Link Width|Link Speed):' "$W/nvme.txt")"

    step "6/9 caches and logs (can take up to 1 minute)"
    echo; echo "--- cache folders (created = when macOS built them; a new cache fills itself in the background)"
    UC=""; UD=""
    if [ -n "$CU" ]; then
      UC=$(sudo -u "$CU" getconf DARWIN_USER_CACHE_DIR 2>/dev/null)
      UD=$(sudo -u "$CU" getconf DARWIN_USER_DIR 2>/dev/null)
    fi
    for p in /Library/Caches/com.apple.iconservices.store "${UC}com.apple.iconservices" "${UC}com.apple.dock.iconcache" "${UD}com.apple.LaunchServices.dv" /System/Volumes/Data/.Spotlight-V100; do
      case "$p" in /*) ;; *) continue;; esac
      if [ -e "$p" ]; then
        bounded 10 du -sk "$p" > "$W/du.txt"
        echo "$(stamps "$p")  size $(kbsize "$W/du.txt") KB  $p"
      else
        echo "not found: $p"
      fi
    done
    echo "## caches created: icon store $(birth /Library/Caches/com.apple.iconservices.store) | user icon cache $(birth "${UC}com.apple.iconservices") | Spotlight index $(birth /System/Volumes/Data/.Spotlight-V100)"
    echo; echo "--- display settings of user ${CU:-?} (read only, read as that user; 1 = on)"
    RT="?"
    if [ -n "$CU" ]; then
      for k in reduceTransparency reduceMotion increaseContrast; do
        v=$(sudo -H -u "$CU" defaults read com.apple.universalaccess "$k" 2>&1 | tail -n 1)
        case "$v" in
          0|1) ;;
          *"does not exist"*|*"Could not find key"*) v="not set or not readable (Apple default: off)";;
          *) v="unreadable: $v";;
        esac
        echo "$k = $v"
        [ "$k" = reduceTransparency ] && RT="$v"
      done
    fi
    echo "## Reduce Transparency (Apple setting, Accessibility > Display): $RT"
    echo; echo "--- APFS TRIM / NVMe kernel lines in the first 15 minutes after this start (log show)"
    boot_log > "$W/apfs.txt"
    echo "TRIM / spaceman lines (first 20):"
    grep -i -E 'trim|spaceman' "$W/apfs.txt" | grep -v -E '^(Timestamp|Filtering)' | head -n 20 | cut -c1-300 | orsay "(none found)"
    echo "NVMe lines: $(grep -c -i 'nvme' "$W/apfs.txt") (first 10):"
    grep -i 'nvme' "$W/apfs.txt" | head -n 10 | cut -c1-300
    grep 'stopped after' "$W/apfs.txt"
    TS=$(trimsum "$W/apfs.txt")
    echo "## APFS TRIM at start: ${TS:-no TRIM line found}"
    echo; echo "--- icon / Spotlight / Launch Services errors and faults in the last hour (log show --last 1h)"
    bounded 40 log show --style compact --last 1h --predicate "$IPRED" > "$W/iconerr.txt"
    grep 'stopped after' "$W/iconerr.txt"
    errcount "$W/iconerr.txt" > "$W/errcount.txt"
    echo "count per process:"
    orsay "(none)" < "$W/errcount.txt"
    echo "most frequent messages (numbers shown as #):"
    errtop "$W/iconerr.txt" | orsay "(none)"
    echo "last 30 lines:"
    grep -E '^[0-9][0-9][0-9][0-9]-' "$W/iconerr.txt" | tail -n 30 | cut -c1-300 | orsay "(none)"
    echo "## log errors+faults last 1 h (icons/Spotlight): $(errsum "$W/errcount.txt")"
    echo; echo "--- crash / hang / CPU-use reports of the last 24 hours (names only)"
    diaglist > "$W/diag.txt"
    orsay "(none)" < "$W/diag.txt"
    echo "## reports last 24 h: $(diagsum "$W/diag.txt")"

    step "7/9 first-run warm-up since this start (one log search, up to 90 s)"
    echo; echo "--- first-run warm-up since this start (log show --last boot)"
    echo "Compare after a normal restart, at about the same uptime. 19 Nov first accelerated login (mode A,"
    echo "boot 21:44:47; that report starts about 20 s after boot): 27 Metal compiler instances, the first at"
    echo "uptime 24 s; 2 WindowServer 'fopen failed for data file' at uptime 24 s; 21 WindowServer 'timed out'."
    bounded 90 log show --style compact --last boot --predicate "$WPRED" > "$W/warm-raw.txt"
    WINC=""
    if grep -q 'stopped after' "$W/warm-raw.txt"; then WINC=" (log search stopped early: counts incomplete)"; echo "$WINC"; fi
    grep -E '^[0-9][0-9][0-9][0-9]-' "$W/warm-raw.txt" > "$W/warm.txt"
    sed -nE 's/^([0-9]{4}-[0-9]{2}-[0-9]{2}) ([0-9]{2}:[0-9]{2}:[0-9]{2})[.0-9]* .*Sandbox: MTLCompilerService\(([0-9]+)\).*/\3 \1 \2/p' "$W/warm.txt" | awk '!seen[$1]++' > "$W/mtl.txt"
    while read -r _p _d _t; do echo "$(upofs "$_d $_t") $_t MTLCompilerService($_p)"; done < "$W/mtl.txt" > "$W/mtlofs.txt"
    NMTL=$(grep -c . "$W/mtlofs.txt")
    MTLFIRST=$(head -n 1 "$W/mtlofs.txt" | awk '{ print $1 }')
    NQ=$(grep -c '^?' "$W/mtlofs.txt")
    [ "$NQ" = 0 ] || WINC="$WINC ($NQ with an unreliable clock time, shown as ?)"
    echo "Metal shader-compiler instances since this start: $NMTL (uptime in s, time, process):"
    orsay "(none)" < "$W/mtlofs.txt"
    grep -E ' WindowServer\[.*timed out' "$W/warm.txt" > "$W/wsto.txt"
    sed -nE 's/^([0-9-]+) ([0-9:]+)[.0-9]* .*/\1 \2/p' "$W/wsto.txt" | while read -r _d _t; do upofs "$_d $_t"; done > "$W/wstoofs.txt"
    NWSTO=$(grep -c . "$W/wsto.txt")
    echo; echo "WindowServer 'timed out' errors since this start: $NWSTO (last 10):"
    tail -n 10 "$W/wsto.txt" | cut -c1-200 | orsay "(none)"
    NFOWS=$(grep -c ' WindowServer\[.*fopen failed for data file' "$W/warm.txt")
    echo; echo "'fopen failed for data file' errors (missing cache files) since this start, per process:"
    grep 'fopen failed for data file' "$W/warm.txt" | awk '{ p = $4; sub(/\[.*/, "", p); print p }' | sort | uniq -c | sort -rn | head -n 15 | orsay "(none)"
    NWK=$(grep -c 'Sandbox: com.apple.WebKit.GPU.*deny' "$W/warm.txt")
    grep -E 'GPURestart|Appears hung|checkGPUProgress' "$W/warm.txt" > "$W/hang.txt"
    NHANG=$(grep -c . "$W/hang.txt")
    echo; echo "GPU hang / restart lines since this start (want none):"
    tail -n 5 "$W/hang.txt" | cut -c1-200 | orsay "(none)"
    NUNC=$(grep -c -E ' disk[0-9]+ reloading after unclean unmount' "$W/warm.txt")
    SHUT=clean
    [ "$NUNC" = 0 ] || SHUT="NOT clean ($NUNC unclean-unmount lines)"
    echo "## warm-up since start: Metal compiler instances $NMTL, by 2/5/7/20 min uptime: $(bycount "$W/mtlofs.txt") (19 Nov first run: 10 / 16 / 21 / 27) | first at uptime ${MTLFIRST:-?} s$WINC"
    echo "## warm-up: WindowServer 'fopen failed for data file' $NFOWS (19 Nov: 2) | WindowServer 'timed out' $NWSTO, by 2/5/7/20 min: $(bycount "$W/wstoofs.txt") (19 Nov: 10 / 16 / 18 / 21) | WebKit GPU sandbox denials $NWK"
    echo "## GPU hang lines since start: $NHANG (want 0) | previous shutdown: $SHUT"

    # battery, powermetrics and the CPU load come last: everything above is already saved if they misbehave
    if [ "$RUN" = full ] && have powermetrics; then
      step "8/9 power at idle: battery and powermetrics (about 50 s)"
      echo; echo "--- battery: 4 samples 5 s apart after 10 s of rest (compare modes A and D on battery, same brightness)"
      sleep 10
      for i in 1 2 3 4; do battery; [ "$i" = 4 ] || sleep 5; done > "$W/bat.txt"
      orsay "(no battery data)" < "$W/bat.txt"
      echo "## battery at idle: $(batsum "$W/bat.txt")"
      echo; echo "--- powermetrics -h (samplers this Mac offers)"
      bounded 10 powermetrics -h > "$W/pmh.txt"
      head -n 80 "$W/pmh.txt"
      PMS=cpu_power
      grep -q 'gpu_power' "$W/pmh.txt" && PMS=cpu_power,gpu_power
      echo; echo "--- powermetrics at idle: --samplers $PMS -i 1000 -n 5 (lines 'duty cycles' left out)"
      bounded 15 powermetrics --samplers "$PMS" -i 1000 -n 5 > "$W/pm-idle.txt"
      if ! grep -q 'Sampled system activity' "$W/pm-idle.txt" && [ "$PMS" != cpu_power ]; then
        echo "(no samples with $PMS; trying cpu_power alone)"
        PMS=cpu_power
        bounded 15 powermetrics --samplers "$PMS" -i 1000 -n 5 > "$W/pm-idle.txt"
      fi
      grep -v 'duty cycles' "$W/pm-idle.txt"
      echo; echo "--- powermetrics smc (temperatures, fans) and thermal pressure at idle, 1 sample each"
      bounded 6 powermetrics --samplers smc -i 1000 -n 1 > "$W/smc-idle.txt"
      bounded 6 powermetrics --samplers thermal -i 1000 -n 1 >> "$W/smc-idle.txt"
      grep -v -E "$HDR" "$W/smc-idle.txt"
      echo "## idle: $(pmsum "$W/pm-idle.txt")"
      echo "## idle sensors: $(sensors "$W/smc-idle.txt")"

      step "9/9 CPU load on all $NCPU CPU threads for about 10 s (it stops by itself; Ctrl+C also stops it)"
      echo; echo "--- CPU load: $NCPU x 'yes > /dev/null' for about 10 s"
      start_load
      echo "load started $(date +%H:%M:%S)"
      sleep 2
      bounded 5 pmset -g therm > "$W/therm-mid.txt"
      echo; echo "--- powermetrics under load: --samplers $PMS -i 1000 -n 5 (lines 'duty cycles' left out)"
      bounded 9 powermetrics --samplers "$PMS" -i 1000 -n 5 > "$W/pm-load.txt"
      grep -v 'duty cycles' "$W/pm-load.txt"
      bounded 4 powermetrics --samplers smc -i 500 -n 1 > "$W/smc-load.txt"
      bounded 5 pmset -g therm > "$W/therm-load.txt"
      echo "load average: $(sysctl -n vm.loadavg 2>/dev/null)"
      stop_load
      echo "load stopped $(date +%H:%M:%S)"
      echo; echo "--- powermetrics smc at the end of the load"
      grep -v -E "$HDR" "$W/smc-load.txt"
      echo; echo "--- pmset -g therm after 2 s of load, then at the end of the load (the values pmset -g thermlog reports)"
      cat "$W/therm-mid.txt"
      echo "..."
      cat "$W/therm-load.txt"
      echo "## load: $(pmsum "$W/pm-load.txt")"
      echo "## load per core type (all $NCPU threads busy; informational): $(coremax "$W/pm-load.txt")"
      echo "## load sensors: $(sensors "$W/smc-load.txt") | pmset after 2 s: $(thermnow "$W/therm-mid.txt") | at end: $(thermnow "$W/therm-load.txt")"
    elif [ "$RUN" = full ]; then
      echo; echo "(powermetrics not found: battery, power measurement and CPU load skipped)"
    else
      step "(quick: steps 8/9 and 9/9, battery, powermetrics and the CPU load, skipped)"
      echo; echo "(quick run: steps 8-9, battery, powermetrics and the CPU load, skipped)"
    fi
  fi
  echo; echo "## runtime: $(( $(date +%s) - T0 )) s"
} > "$OUT" 2>&1
sync
echo
echo "Saved: $OUT"
echo
echo "===== SUMMARY (all details are in the report) ====="
grep '^## ' "$OUT" | sed 's/^## //' | cut -c1-260
echo
if [ "$RUN" = watch ]; then
  echo "How to read: GPU clock clearly above its 'before' value and RC6 well below 100% while you clicked"
  echo "= the GPU was working normally. Clock stuck at its minimum while RC6 stays low = GPU frequency"
  echo "control problem (report it upstream; there is no user fix). Most CPU seconds in iconservices ="
  echo "icons were being drawn; in Spotlight (mds*) = background indexing competed; in Metal compiler ="
  echo "shaders were being compiled (should shrink once the Metal caches are built)."
  echo "Then quit the app (Cmd+Q), open it again, note whether the icons are instant now, and continue with 01-STEPS.txt."
else
  echo "How to read: mds*/iconservices CPU seconds that keep growing between two runs = macOS is still"
  echo "building its Spotlight index / icon cache. 'USB stick indexed: yes' = Spotlight also indexes this"
  echo "OpenCore USB stick (extra background work). After a normal restart, far fewer Metal compiler"
  echo "instances and no 'fopen failed' than on 19 Nov = the caches are warm (a first-run effect)."
  echo "recoveryCount or GPU hang lines above 0 = the GPU driver had to recover the GPU. CPU_Speed_Limit"
  echo "below 100, or a 'limited by' reason other than TURBO_ATTENUATION and MAX_TURBO_LIMIT = a heat or"
  echo "power limit (only indicative on this Alder Lake with a spoofed CPU ID)."
  if [ "$RUN" = quick ]; then echo "Then continue with 01-STEPS.txt."; else echo "Then boot Windows and tell Claude: perf report"; fi
fi
