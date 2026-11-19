#!/bin/bash
# G15 5520: remove EVERYTHING NullMoth / 1401 installed inside macOS, then rebuild the kernel collection
# by reinstalling WhateverXe-Graphics-0.4.4.pkg (verified). Does NOT touch the EFI on the USB.
# Keeps: WhateverXe-Graphics files (AppleIntelTGL*, Xe* bundles), Apple files, your apps and downloads,
#        your login settings. Saves a before-report in G15-GUIDE/reports/.
# Run from maintenance mode:  sudo bash /Volumes/1401/G15-GUIDE/03-remove-nullmoth.sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
DIR="$(cd "$(dirname "$0")" && pwd)"
USB="$(cd "$DIR/.." && pwd)"
PKG="$USB/WhateverXe-Graphics-0.4.4.pkg"
PKG_SHA=f4c2d680a7c52c33a3f038ce6945da0aa2cc044e62b935a52ea046c7c473cfec
G=7C436110-AB2A-4BBB-A880-FE41995C9F82
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
NAMES=" NVRM NVRMFB NVAccel NVRMAGDC NVPrimarySelector NMXAudio NMIntelFB NMGopFB NMXGPU NMXAccel NMXNPU NMSMN NMHDA NMKbdBacklight "

# ---------------------------------------------------------------- checks (nothing changed yet)
if [ "$(id -u)" != 0 ]; then echo "STOP: run it with sudo:  sudo bash \"$0\"   Nothing was changed."; exit 1; fi
S=$(csrutil status 2>/dev/null)
if printf '%s\n' "$S" | grep -q 'status: enabled\.' || printf '%s\n' "$S" | grep -q 'Filesystem Protections: enabled'; then
  echo "STOP: SIP file protection is on. Start macOS from the USB OpenCore and run again. Nothing was changed."; exit 1
fi
R="$DIR/reports"; mkdir -p "$R" 2>/dev/null || R=/Users/Shared
OUT="$R/nullmoth-removal-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT" || { echo "STOP: cannot write $OUT. Nothing was changed."; exit 1; }
exec > >(tee -a "$OUT/log.txt") 2>&1
VER=$(sw_vers -productVersion)
RERUN=0
echo "macOS $VER   report folder: $OUT"
[ "$(sysctl -n kern.safeboot 2>/dev/null)" = 1 ] && echo "Safe Mode: yes"
case " $(nvram boot-args 2>/dev/null | cut -f2-) " in
  *" -wexoff "*) echo "Mode: MAINTENANCE (good)";;
  *) echo "NOTE: not in maintenance mode. Close all other apps before continuing.";;
esac
echo
echo "This removes from macOS everything NullMoth/1401 installed:"
echo "  launch services and login agents, NVIDIA + GPU-test + hybrid + experimental kexts, Metal/Vulkan parts,"
echo "  /Library/NullMoth, NVRAM flags, the 1401 app (not the copy on this USB), then rebuilds the kernel collection."
echo "It keeps WhateverXe Graphics, Apple files, your apps, downloads and login settings."
echo "Do not use the laptop while it runs (5-10 minutes)."
read -r -p "Type YES to continue: " ans
[ "$ans" = "YES" ] || { echo "Cancelled. Nothing was changed."; exit 0; }

# ---------------------------------------------------------------- 1. before-report (read-only)
echo; echo "== 1/9 saving a before-report"
{
  echo "=== before removal $(date)"; sw_vers; uname -v; printf '%s\n' "$S"
  echo "--- NVRAM"; nvram -p 2>/dev/null | grep -iE 'boot-args|csr-active-config|nullmoth'
  echo "--- kexts (path, bundle id)"
  for k in /Library/Extensions/*.kext /Library/StagedExtensions/Library/Extensions/*.kext; do
    [ -d "$k" ] || continue
    echo "$k  $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$k/Contents/Info.plist" 2>/dev/null)"
  done
  echo "--- loaded"; kmutil showloaded --list-only 2>/dev/null | grep -iE 'nullmoth|NVPrimary|TGL|whateverxe|amfi'
  echo "--- aux KC contents"; kmutil inspect -a x86_64 -A "$KC" 2>/dev/null | grep -iE 'nullmoth|NVPrimary|TGL'
  ls -la /Library/KernelCollections
  echo "--- GPUBundles"; ls -la /Library/GPUBundles
  echo "--- launch jobs"
  ls -la /Library/LaunchDaemons/com.nullmoth.* /Library/LaunchAgents/com.nullmoth.* /Users/*/Library/LaunchAgents/com.nullmoth.* 2>/dev/null
  launchctl print system 2>/dev/null | grep -i 'com\.nullmoth'
  echo "--- /Library/NullMoth"; ls -la /Library/NullMoth 2>&1
  for f in state experimental hybrid xe-state gputest-reenabled power-profile.backup added-boot-args driver-restored os-major driver-version gpuboost update-pending; do
    [ -f "/Library/NullMoth/$f" ] && { echo "--- $f"; cat "/Library/NullMoth/$f"; }
  done
  for f in lastgood.log bootguard.log recover.log osupdate.log backlight.log; do
    [ -f "/Library/NullMoth/$f" ] && { echo "--- last lines of $f"; tail -n 20 "/Library/NullMoth/$f"; }
  done
  echo "--- PCI display/audio functions (vendor:device class)"
  ioreg -r -c IOPCIDevice -l -w0 | LC_ALL=C awk -F'<|>' 'function out(){ if (v != "") print n, v ":" d, "class", c }
    /\+-o /{ out(); n=$0; sub(/^[ |]*\+-o /, "", n); sub(/  <class.*/, "", n); v=""; d=""; c="" }
    /"vendor-id" =/{ v=substr($2,3,2) substr($2,1,2) }
    /"device-id" =/{ d=substr($2,3,2) substr($2,1,2) }
    /"class-code" =/{ c=substr($2,5,2) substr($2,3,2) substr($2,1,2) }
    END{ out() }' | grep -E 'class 0[34]'
  echo "--- NMXAudio attachment"; ioreg -w0 -t -c NMXAudio 2>/dev/null | grep -- '+-o' | tail -n 6
  echo "--- audio devices"; system_profiler SPAudioDataType 2>/dev/null
  echo "--- receipts"; pkgutil --pkgs | grep -iE 'whateverxe|nullmoth'
  echo "--- 1401 app copies"; mdfind 'kMDItemCFBundleIdentifier == "com.nullmoth.1401"' 2>/dev/null
} > "$OUT/before.txt" 2>&1
for k in /Library/Extensions/*.kext; do
  [ -d "$k" ] || continue
  case "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$k/Contents/Info.plist" 2>/dev/null)" in
    com.nullmoth.*|org.hackintosh.experimental.NVPrimarySelector) plutil -p "$k/Contents/Info.plist" > "$OUT/Info-$(basename "$k").txt" 2>&1;;
  esac
done
if [ -d /Library/NullMoth ]; then
  ls -laR /Library/NullMoth > "$OUT/NullMoth-listing.txt" 2>&1
  tar -czf "$OUT/NullMoth-records.tgz" -C /Library --exclude 'NullMoth/nvfw' --exclude 'NullMoth/firmware' --exclude 'NullMoth/kexts' --exclude 'NullMoth/backup-*' --exclude 'NullMoth/gpu-userland' --exclude 'NullMoth/npu' --exclude 'NullMoth/dlss' --exclude 'NullMoth/licenses' --exclude 'NullMoth/boost' --exclude 'NullMoth/ryzenadj' --exclude 'NullMoth/arm' --exclude 'NullMoth/gamemode' --exclude 'NullMoth/LogoutHook' NullMoth >/dev/null 2>&1
fi
[ -f /Library/NullMoth/arm/uninstall.sh ] && cp -p /Library/NullMoth/arm/uninstall.sh "$OUT/arm-uninstall.sh.txt"
echo "saved $OUT/before.txt"

# ---------------------------------------------------------------- 2. stop + delete NullMoth launch jobs FIRST
echo; echo "== 2/9 stopping NullMoth background services and login agents"
for l in recover osupdate lastgood bootguard backlight gamemode nvmtl-boost ryzen-power wsreset displaytrace; do
  launchctl bootout "system/com.nullmoth.$l" >/dev/null 2>&1
done
for p in /Library/LaunchDaemons/com.nullmoth.*.plist; do
  [ -e "$p" ] || continue
  launchctl bootout system "$p" >/dev/null 2>&1
  rm -f "${p:?}" && echo "removed $p"
done
for UH in /Users/*; do
  U=${UH##*/}
  N=$(id -u "$U" 2>/dev/null) || continue
  for l in gamemode.indicator crashcheck tester reacheddesktop; do
    launchctl bootout "gui/$N/com.nullmoth.$l" >/dev/null 2>&1
  done
  for p in /Library/LaunchAgents/com.nullmoth.*.plist "$UH"/Library/LaunchAgents/com.nullmoth.*.plist; do
    [ -e "$p" ] && launchctl bootout "gui/$N" "$p" >/dev/null 2>&1
  done
  for p in "$UH"/Library/LaunchAgents/com.nullmoth.*.plist; do
    [ -e "$p" ] && rm -f "${p:?}" && echo "removed $p"
  done
done
for p in /Library/LaunchAgents/com.nullmoth.*.plist; do
  [ -e "$p" ] && rm -f "${p:?}" && echo "removed $p"
done
if [ -f /Library/PrivilegedHelperTools/ryzenadj ] && LC_ALL=C grep -aq 'com.nullmoth.ryzenadj' /Library/PrivilegedHelperTools/ryzenadj; then
  rm -f /Library/PrivilegedHelperTools/ryzenadj && echo "removed /Library/PrivilegedHelperTools/ryzenadj"
fi
for F in /Library/PrivilegedHelperTools/com.nullmoth.*; do
  [ -e "$F" ] && rm -rf "${F:?}" && echo "removed $F"
done
if [ -x /Library/NullMoth/LogoutHook/Launchd.command ]; then (cd /Library/NullMoth/LogoutHook && ./Launchd.command uninstall); fi
rm -rf /usr/local/libexec/nullmoth
if launchctl print system 2>/dev/null | grep -qi 'com\.nullmoth'; then
  echo "NOTE: still loaded (gone after restart):"; launchctl print system 2>/dev/null | grep -i 'com\.nullmoth'
else echo "OK: no NullMoth service running"; fi

# ---------------------------------------------------------------- 3. NullMoth kexts (by bundle id or exact name)
echo; echo "== 3/9 removing NullMoth kexts"
for D in /Library/Extensions /Library/StagedExtensions/Library/Extensions; do
  [ -d "$D" ] || continue
  for k in "$D"/*.kext; do
    [ -d "$k" ] || continue
    n=$(basename "$k" .kext)
    id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$k/Contents/Info.plist" 2>/dev/null)
    hit=0
    case "$id" in com.nullmoth.*|org.hackintosh.experimental.NVPrimarySelector) hit=1;; esac
    case "$NAMES" in *" $n "*) hit=1;; esac
    case "$n" in AppleIntelTGL*) hit=0;; esac
    if [ "$hit" = 1 ]; then rm -rf "${k:?}" && echo "removed $k (${id:-no bundle id})"; fi
  done
done
rm -f "$KC.nullmoth-install-new" "$KC.nullmoth-update-new" "$KC.nullmoth-remove-new"
if grep -lE 'com\.nullmoth|NVPrimarySelector' /Library/Extensions/*.kext/Contents/Info.plist 2>/dev/null; then
  echo "PROBLEM: the kext(s) above are still in /Library/Extensions"
else echo "OK: no NullMoth kext left in /Library/Extensions"; fi
ls -d /Library/Extensions/AppleIntelTGL*.kext 2>/dev/null || echo "NOTE: WhateverXe Graphics kexts not present yet (step 9 installs them)"

# ---------------------------------------------------------------- 4. Metal / Vulkan parts
echo; echo "== 4/9 removing NullMoth Metal/Vulkan parts"
GB=/Library/GPUBundles
for b in NVMTLDriver.bundle NVIDIAShared.bundle nvmtl nvmtl-allow.txt nvmtl-gpu-policy.txt nvmtl-gpupass-probe; do
  [ -e "$GB/$b" ] && rm -rf "${GB:?}/${b:?}" && echo "removed $GB/$b"
done
rm -f /Library/Extensions/nvmtl-allow.txt
if [ -f /System/Volumes/Preboot/Cryptexes/OS/Library/GPUBundles/.nullmoth-safari-copy ]; then
  rm -rf /System/Volumes/Preboot/Cryptexes/OS/Library/GPUBundles/NVMTLDriver.bundle
  rm -f /System/Volumes/Preboot/Cryptexes/OS/Library/GPUBundles/.nullmoth-safari-copy
  rmdir /System/Volumes/Preboot/Cryptexes/OS/Library/GPUBundles 2>/dev/null
  echo "removed the Safari GPU copy"
fi
rm -f /usr/local/share/vulkan/icd.d/nullmoth_nvk_icd.json
if [ -f /usr/local/lib/libvulkan.1.dylib ] && [ ! -L /usr/local/lib/libvulkan.1.dylib ]; then
  case "$(shasum -a 256 /usr/local/lib/libvulkan.1.dylib | cut -d' ' -f1)" in
    fb8c51189d2d63ff3311c0b837ccb514fb606751c8908d3be0db9f28efd8645a|dc81d04917bd1aad88b2ec150ff3150f44dd24b786b227874492aae62e7c9c6e)
      rm -f /usr/local/lib/libvulkan.1.dylib && echo "removed NullMoth's Vulkan loader";;
  esac
fi
rm -f /usr/local/etc/nvencvt.conf
rm -rf "/Library/Application Support/NullMoth"
if security authorizationdb read com.nullmoth.1401.diagnostics.capture >/dev/null 2>&1; then
  security authorizationdb remove com.nullmoth.1401.diagnostics.capture >/dev/null 2>&1
fi

# ---------------------------------------------------------------- 5. undo NullMoth power profile and ARM translator
echo; echo "== 5/9 undoing NullMoth system changes"
B=/Library/NullMoth/power-profile.backup
if [ -s "$B" ]; then
  while read -r k v; do
    case "$k" in
      powernap|standby|autopoweroff|proximitywake|hibernatemode)
        case "$v" in ''|*[!0-9]*) ;; *) pmset -a "$k" "$v" && echo "restored pmset $k $v";; esac;;
    esac
  done < "$B"
fi
CU=$(stat -f %Su /dev/console 2>/dev/null)
A=/Library/NullMoth/arm/uninstall.sh
if [ -f "$A" ]; then
  o=$(stat -f %u "$A"); m=$(stat -f %Lp "$A")
  case "$m" in
    *[2367]?|*[2367]) echo "NOTE: $A is writable by other users - not run";;
    *) if [ "$o" = 0 ] && [ -n "$CU" ] && [ "$CU" != root ]; then /bin/bash "$A" --user "$CU"; echo "ARM uninstaller exit status $?"; fi;;
  esac
fi
rm -rf "/Applications/NullMoth ARM" /Users/*/Applications/"NullMoth ARM"

# ---------------------------------------------------------------- 6. /Library/NullMoth and system leftovers
echo; echo "== 6/9 removing /Library/NullMoth and leftovers"
rm -rf /Library/NullMoth /Users/Shared/nvfw
rm -rf /private/var/tmp/nullmoth* /private/var/tmp/1401-run.* /private/var/root/1401-logs.* /private/var/root/1401-operation.* /private/var/root/nullmoth-arm.*
rm -rf /private/tmp/nullmoth-xrt.* /private/tmp/nvmtl*
rm -rf /private/var/folders/*/*/C/nvmtl /private/var/folders/*/*/C/nvmtl-mesa /private/var/folders/*/*/T/nvmtl* /private/var/folders/*/*/T/1401-logs.*
rm -rf /private/var/root/Library/Caches/nvmtl /private/var/root/.cache/mesa_shader_cache /private/var/root/.cache/mesa_shader_cache_db /private/var/root/.cache/mesa_shader_cache_sf
if [ -e /Library/NullMoth ]; then echo "PROBLEM: /Library/NullMoth could not be removed"; else echo "OK: /Library/NullMoth is gone"; fi

# ---------------------------------------------------------------- 7. per-user leftovers + the 1401 app
echo; echo "== 7/9 removing 1401 app data and the app"
for UH in /Users/*; do
  U=${UH##*/}
  id -u "$U" >/dev/null 2>&1 || continue
  [ -d "$UH/Library" ] || continue
  sudo -u "$U" tccutil reset All com.nullmoth.1401 >/dev/null 2>&1
  sudo -u "$U" defaults delete com.nullmoth.1401 >/dev/null 2>&1
  for p in "Library/Application Support/NullMoth" "Library/Logs/NullMoth" "Library/Caches/com.nullmoth.1401" "Library/WebKit/com.nullmoth.1401" "Library/HTTPStorages/com.nullmoth.1401" "Library/HTTPStorages/com.nullmoth.1401.binarycookies" "Library/Cookies/com.nullmoth.1401.binarycookies" "Library/Saved Application State/com.nullmoth.1401.savedState" "Library/Preferences/com.nullmoth.1401.plist" "Library/Caches/nvmtl" ".cache/mesa_shader_cache" ".cache/mesa_shader_cache_db" ".cache/mesa_shader_cache_sf" "Applications/NullMoth ARM"; do
    [ -e "$UH/$p" ] && rm -rf "${UH:?}/${p:?}" && echo "removed $UH/$p"
  done
  rm -f "${UH:?}"/Library/Preferences/ByHost/com.nullmoth.1401.*.plist
  for f in "$UH"/Desktop/1401-crash-*.txt; do
    [ -f "$f" ] && cp -p "$f" "$OUT/" && echo "copied $f to the report"
  done
done
tccutil reset All com.nullmoth.1401 >/dev/null 2>&1
{ echo /Applications/1401.app
  for UH in /Users/*; do echo "$UH/Applications/1401.app"; echo "$UH/Desktop/1401.app"; echo "$UH/Downloads/1401.app"; done
  mdfind 'kMDItemCFBundleIdentifier == "com.nullmoth.1401"' 2>/dev/null
} | while IFS= read -r a; do
  case "$a" in ''|/Volumes/*) continue;; esac
  [ -d "$a" ] || continue
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$a/Contents/Info.plist" 2>/dev/null)" = com.nullmoth.1401 ] || continue
  rm -rf "${a:?}" && echo "removed $a"
done

# ---------------------------------------------------------------- 8. NVRAM flags
echo; echo "== 8/9 clearing NullMoth NVRAM flags"
for n in nullmoth-remove nullmoth-nv-starts nullmoth-nv-ok nullmoth-ws-loop nullmoth-backlight nullmoth-audio-attaching nullmoth-audio-state nullmoth-ifb-step nullmoth-gpu-attaching nullmoth-npu-attaching; do
  nvram -d "$G:$n" >/dev/null 2>&1
done
nvram -p 2>/dev/null | cut -f1 | grep -i 'nullmoth' | while IFS= read -r v; do nvram -d "$v" >/dev/null 2>&1; done
if nvram -p 2>/dev/null | grep -qi nullmoth; then echo "NOTE: still in NVRAM (harmless once NullMoth is gone):"; nvram -p 2>/dev/null | grep -i nullmoth
else echo "OK: no nullmoth NVRAM flag"; fi

# ---------------------------------------------------------------- 9. rebuild the kernel collection (WhateverXe Graphics reinstall)
echo; echo "== 9/9 reinstalling WhateverXe Graphics 0.4.4 (rebuilds the kernel collection; takes a few minutes)"
H=$(shasum -a 256 "$PKG" 2>/dev/null | cut -d' ' -f1)
REBUILT=0
if [ "$H" != "$PKG_SHA" ]; then
  echo "STOP: $PKG is missing or not the verified 0.4.4 package. Do NOT restart; boot Windows and tell Claude."
elif nice -n 10 installer -pkg "$PKG" -target /; then
  REBUILT=1
else
  echo "NOTE: the package installer did not finish (macOS $VER). Rebuilding the collection directly."
  set --
  for k in /Library/Extensions/*.kext; do [ -d "$k" ] && set -- "$@" -p "$k"; done
  if [ "$#" -eq 0 ]; then
    if [ -f "$KC" ] && kmutil inspect -a x86_64 -A "$KC" 2>/dev/null | grep -qiE 'com\.nullmoth|NVPrimarySelector'; then
      mv -f "$KC" "$OUT/old-AuxiliaryKernelExtensions.kc" && echo "no third-party kexts left: old NullMoth collection moved into the report folder"
    fi
    REBUILT=1
  else
    W=$(mktemp -d /Library/KernelCollections/.G15.XXXXXX)
    if nice -n 10 kmutil create -n aux -x -z -V release -r /Library/Extensions --allow-missing-kdk "$@" \
         -B /System/Library/KernelCollections/BootKernelExtensions.kc \
         -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
         -A "$W/AuxiliaryKernelExtensions.kc" --no-authentication \
       && chmod 0644 "$W/AuxiliaryKernelExtensions.kc" && mv -f "$W/AuxiliaryKernelExtensions.kc" "$KC"; then
      REBUILT=1
    else
      echo "NOTE: the kernel collection could not be rebuilt in this mode (this can happen in Safe Mode)."
      if [ -f "$KC" ]; then
        mv -f "$KC" "$OUT/old-AuxiliaryKernelExtensions.kc" && echo "The old collection (with NullMoth inside) was moved into the report folder, so the next start cannot load NullMoth."
      fi
      REBUILT=1; RERUN=1
    fi
    rm -rf "${W:?}"
  fi
  RERUN=1
  MAJ=${VER%%.*}; MIN=${VER#*.}; MIN=${MIN%%.*}
  if [ "$MAJ" = 26 ] && [ "${MIN:-0}" -lt 7 ]; then
    echo "IMPORTANT: Iris Xe acceleration needs macOS 26.7 or newer. Update first: System Settings > General >"
    echo "           Software Update > macOS Tahoe 26.7.x only (never macOS 27), then run this script again."
  fi
fi

echo
if [ "$REBUILT" = 1 ]; then
  LEFT=""
  [ -f "$KC" ] && kmutil inspect -a x86_64 -A "$KC" 2>/dev/null | grep -qiE 'com\.nullmoth|NVPrimarySelector' && LEFT="$LEFT kernel-collection"
  grep -qE 'com\.nullmoth|NVPrimarySelector' /Library/Extensions/*.kext/Contents/Info.plist 2>/dev/null && LEFT="$LEFT /Library/Extensions"
  [ -e /Library/NullMoth ] && LEFT="$LEFT /Library/NullMoth"
  ls /Library/LaunchDaemons/com.nullmoth.* /Library/LaunchAgents/com.nullmoth.* /Users/*/Library/LaunchAgents/com.nullmoth.* >/dev/null 2>&1 && LEFT="$LEFT launch-agents"
  if [ -n "$LEFT" ]; then
    echo "STOP: NullMoth is still present in:$LEFT. Do NOT restart; boot Windows and tell Claude (report: $OUT)."
    exit 1
  fi
  echo "OK: nothing from NullMoth is left."
  echo "Kernel collection graphics drivers:"; kmutil inspect -a x86_64 -A "$KC" 2>/dev/null | grep -i 'TGL'
  pkgutil --pkgs | grep -i whateverxe
  echo
  if [ "${RERUN:-0}" = 1 ]; then
    echo "DONE (part 1). NullMoth is removed; the graphics package still has to be installed."
    echo "After the restart (normal maintenance mode) run this script again:  sudo bash $DIR/03-remove-nullmoth.sh"
  else
    echo "DONE. NullMoth is removed and WhateverXe Graphics is installed."
  fi
  echo "Report: $OUT"
else
  exit 1
fi
