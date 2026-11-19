#!/bin/bash
# G15 5520 Iris Xe check. Collects information + logs of earlier frozen starts into reports/ on this USB.
# It does NOT change anything. Run:  sudo bash /Volumes/1401/G15-GUIDE/02-check.sh
DIR="$(cd "$(dirname "$0")" && pwd)"
USB="$(cd "$DIR/.." && pwd)"
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$DIR/reports"
OUT="$DIR/reports/report-$STAMP.txt"
CU=$(stat -f %Su /dev/console 2>/dev/null)
UH=$(eval echo "~$CU")
echo "Collecting information (1 to 3 minutes, please wait and do not use the laptop)..."
{
  echo "=== G15 report $(date) ==="
  case " $(nvram boot-args 2>/dev/null) " in
    *" -wexoff "*) echo "MODE: MAINTENANCE (WhateverXe off)";;
    *" -wex-noaccel "*) echo "MODE: N (WhateverXe display only)";;
    *) echo "MODE: ACCELERATED (WhateverXe on)";;
  esac
  echo; echo "--- macOS version"; sw_vers
  echo; echo "--- kernel"; uname -v
  echo; echo "--- uptime"; uptime
  echo; echo "--- SIP"; csrutil status
  echo; echo "--- NVRAM boot-args / csr / NullMoth"; nvram -p 2>/dev/null | grep -iE 'boot-args|csr-active-config|nullmoth|revpatch'
  echo; echo "--- AMFIAnchor (want InstallStatus = 1)"; ioreg -r -c AMFIAnchor -l 2>/dev/null | grep -E 'InstallStatus|LoadedAnchors'
  echo; echo "--- loaded kexts (graphics / AMFI / NullMoth)"
  kmutil showloaded --list-only 2>/dev/null | grep -iE 'whateverxe|amfianchor|amfipass|lilu|TGL|nullmoth|NMX|NVRM|NVAccel|NVPrimary|NMIntel|NMGop|CpuTopology'
  echo; echo "--- WhateverXe Graphics package receipts"; pkgutil --pkgs | grep -i whateverxe
  echo; echo "--- /Library/Extensions"; ls -la /Library/Extensions
  echo; echo "--- /Library/GPUBundles"; ls -la /Library/GPUBundles 2>&1
  echo; echo "--- NullMoth leftovers (want: nothing listed)"
  ls -d /Library/NullMoth /Library/GPUBundles/nvmtl /Library/GPUBundles/NVMTLDriver.bundle 2>/dev/null
  ls /Library/LaunchDaemons/com.nullmoth.* /Library/LaunchAgents/com.nullmoth.* /Users/*/Library/LaunchAgents/com.nullmoth.* 2>/dev/null
  launchctl print system 2>/dev/null | grep -i 'com\.nullmoth'
  echo; echo "--- CPU"; sysctl hw.physicalcpu hw.logicalcpu machdep.cpu.thread_count machdep.cpu.brand_string 2>/dev/null
  echo; echo "--- power settings"; pmset -g 2>/dev/null
  echo; echo "--- displays"; system_profiler SPDisplaysDataType
  echo; echo "--- graphics accelerator objects"; ioreg -r -c IOAccelerator -d 1 2>/dev/null | head -40
  echo; echo "--- WhateverXe display admission (for upstream triage)"; ioreg -lw0 -r -k N97Admission -d1 2>/dev/null | head -60
  echo; echo "--- panic files saved by OpenCore on the USB"; ls -la "$USB"/panic-*.txt 2>/dev/null
  echo; echo "--- previous shutdown causes (last 24 hours)"
  log show --last 24h --style compact --predicate 'eventMessage CONTAINS "Previous shutdown cause"' 2>/dev/null | tail -15
  echo; echo "--- kernel / WindowServer problems in the last 24 hours (includes frozen starts)"
  log show --last 24h --style compact --predicate '(process == "kernel" AND (eventMessage CONTAINS[c] "wex" OR eventMessage CONTAINS[c] "WhateverXe" OR eventMessage CONTAINS[c] "AMFIAnchor" OR eventMessage CONTAINS[c] "TGL" OR eventMessage CONTAINS[c] "IntelAccel" OR eventMessage CONTAINS[c] "IOGPU" OR eventMessage CONTAINS[c] "GPURestart" OR eventMessage CONTAINS[c] "GPU restart" OR eventMessage CONTAINS[c] "checkGPUProgress" OR eventMessage CONTAINS[c] "Appears hung" OR eventMessage CONTAINS[c] "Multi-Context" OR eventMessage CONTAINS[c] "Link loss" OR eventMessage CONTAINS[c] "link training" OR eventMessage CONTAINS[c] "spinlock" OR eventMessage CONTAINS[c] "watchdog" OR eventMessage CONTAINS[c] "IGFB" OR eventMessage CONTAINS[c] "N97" OR eventMessage CONTAINS[c] "Display13" OR eventMessage CONTAINS[c] "hang" OR eventMessage CONTAINS[c] "timeout" OR eventMessage CONTAINS[c] "nullmoth" OR eventMessage CONTAINS[c] "NVRM")) OR (process == "WindowServer" AND (messageType == error OR messageType == fault))' 2>/dev/null | tail -800
} > "$OUT" 2>&1
# copy recent crash / hang / panic / GPU-restart reports (last 24 hours) and OpenCore panic files
DD="$DIR/reports/diag-$STAMP"
mkdir -p "$DD"
for d in /Library/Logs/DiagnosticReports "$UH/Library/Logs/DiagnosticReports"; do
  [ -d "$d" ] && find "$d" -maxdepth 2 -type f -mmin -1440 \( -name '*.panic' -o -name '*.ips' -o -name '*.hang' -o -name '*.spin' -o -name '*.diag' -o -name '*.gpuRestart' \) -exec cp {} "$DD/" \; 2>/dev/null
done
cp "$USB"/panic-*.txt "$DD/" 2>/dev/null
echo "Saved: $OUT"
echo "Crash/hang/panic reports copied: $(ls "$DD" | wc -l | tr -d ' ')"
echo
grep -E 'MODE:|ProductVersion|InstallStatus|VRAM|Metal|Resolution|UI Looks like' "$OUT"
