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
  echo; echo "--- RestrictEvents revpatch (want sbvmm,cpuname)"; nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:revpatch 2>&1
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
  pgrep -lx 1401
  sfltool dumpbtm 2>/dev/null | grep -iE 'nullmoth|1401'
  echo; echo "--- CPU"; sysctl hw.physicalcpu hw.logicalcpu machdep.cpu.thread_count machdep.cpu.brand_string machdep.xcpm.mode 2>/dev/null
  echo; echo "--- power settings"; pmset -g 2>/dev/null
  echo; echo "--- test mode state (want: indexing disabled on this USB; mediaanalysisd + photoanalysisd disabled)"
  mdutil -s "$USB" 2>&1
  launchctl print-disabled "gui/$(id -u "$CU")" 2>/dev/null | grep -E 'mediaanalysisd|photoanalysisd'
  echo; echo "--- displays"; system_profiler SPDisplaysDataType
  echo; echo "--- NVIDIA dGPU seen by macOS (mode D turns it off: want 0 there)"
  echo "NVIDIA dGPU devices visible: $(ioreg -l -w0 2>/dev/null | grep -c '"vendor-id" = <de100000>')"
  ioreg -r -n NHG1 -d 1 2>/dev/null | head -3
  echo; echo "--- graphics accelerator objects"; ioreg -r -c IOAccelerator -d 1 2>/dev/null | head -120
  echo; echo "--- WhateverXe display admission (for upstream triage)"; ioreg -lw0 -r -k N97Admission -d1 2>/dev/null
  echo; echo "--- WhateverXe status keys"; ioreg -l -d1 -w0 2>/dev/null | grep -E 'WhateverXeDataAccess|WhateverXeWebKit|TGLIRQLive|N97GTFaultCapture|TGLHostObservation|TGLCSB12'
  echo; echo "--- backlight"; ioreg -lw0 2>/dev/null | grep -E 'WhateverXeBacklight|TGLBacklightPWM'
  echo; echo "--- Bluetooth (want: bluetoothd running, FirmwareLoaded = Yes, 0 bluetoothd corpses)"
  pgrep -lx bluetoothd
  ioreg -p IOUSB -l -w0 2>/dev/null | grep -E '"FirmwareLoaded"|Bluetooth USB Host Controller'
  nvram bluetoothExternalDongleFailed 2>&1
  echo "bluetoothd corpses this boot: $(log show --last boot --style compact --predicate 'eventMessage CONTAINS "corpse enqueued for bluetoothd"' 2>/dev/null | grep -c bluetoothd)"
  system_profiler SPBluetoothDataType 2>/dev/null | grep -E 'State:|Chipset:|Transport:'
  echo; echo "--- panic files saved by OpenCore on the USB (stays empty on this laptop; see the markers below)"; ls -la "$USB"/panic-*.txt 2>/dev/null
  echo; echo "--- OpenCore logs whose previous macOS session panicked (EB|P:MPI] Y)"; grep -a -l -F 'EB|P:MPI] Y' "$USB"/opencore-*.txt 2>/dev/null
  echo; echo "--- previous shutdown causes (last 24 hours)"
  log show --last 24h --style compact --predicate 'eventMessage CONTAINS "Previous shutdown cause"' 2>/dev/null | tail -40
  echo; echo "--- this boot's start: graphics / ACPI / dGPU-off lines"
  log show --last boot --style compact --predicate 'process == "kernel" AND (eventMessage CONTAINS "[IGPU]" OR eventMessage CONTAINS "IGFB" OR eventMessage CONTAINS "AGDP" OR eventMessage CONTAINS[c] "ACPI Error" OR eventMessage CONTAINS[c] "ACPI Exception" OR eventMessage CONTAINS "NHG1")' 2>/dev/null | head -300
  echo; echo "--- kernel / WindowServer problems in the last 24 hours (includes frozen starts)"
  log show --last 24h --style compact --predicate '(process == "kernel" AND (eventMessage CONTAINS[c] "wex" OR eventMessage CONTAINS[c] "WhateverXe" OR eventMessage CONTAINS[c] "AMFIAnchor" OR eventMessage CONTAINS[c] "TGL" OR eventMessage CONTAINS[c] "IntelAccel" OR eventMessage CONTAINS[c] "IOGPU" OR eventMessage CONTAINS[c] "GPURestart" OR eventMessage CONTAINS[c] "GPU restart" OR eventMessage CONTAINS[c] "checkGPUProgress" OR eventMessage CONTAINS[c] "Appears hung" OR eventMessage CONTAINS[c] "Multi-Context" OR eventMessage CONTAINS[c] "Link loss" OR eventMessage CONTAINS[c] "link training" OR eventMessage CONTAINS[c] "spinlock" OR eventMessage CONTAINS[c] "watchdog" OR eventMessage CONTAINS[c] "IGFB" OR eventMessage CONTAINS[c] "N97" OR eventMessage CONTAINS[c] "Display13" OR eventMessage CONTAINS[c] " hang" OR eventMessage CONTAINS[c] "hung" OR eventMessage CONTAINS[c] "timeout" OR eventMessage CONTAINS[c] "nullmoth" OR eventMessage CONTAINS[c] "NVRM")) OR (process == "WindowServer" AND (messageType == error OR messageType == fault))' 2>/dev/null | tail -800
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
grep -E 'MODE:|ProductVersion|InstallStatus|VRAM|Metal|Resolution|UI Looks like|NVIDIA dGPU devices|FirmwareLoaded|revpatch|bluetoothd corpses' "$OUT"
