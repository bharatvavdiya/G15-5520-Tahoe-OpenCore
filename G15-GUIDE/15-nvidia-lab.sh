#!/bin/bash
# G15 NVIDIA mode (mode 9) on your normal macOS: NullMoth 3.1 drives the RTX 3050 while the BIOS sends the screen to
# the NVIDIA card. In the Iris Xe modes (A, D, MAINTENANCE...) the boot-arg -nvoff parks every NullMoth kext, and
# AMFI/SIP stay as they are; only mode 9 turns AMFI off and sets SIP 0xA43.
#   bash      /Volumes/1401/G15-GUIDE/15-nvidia-lab.sh check      (read-only status; works in every mode)
#   sudo bash /Volumes/1401/G15-GUIDE/15-nvidia-lab.sh nullmoth   (in MAINTENANCE: install the verified NullMoth 3.1)
#   sudo bash /Volumes/1401/G15-GUIDE/15-nvidia-lab.sh remove     (in MAINTENANCE: remove NullMoth, Iris Xe as before)
# Never use the 1401 app: it rewrites the OpenCore config on this USB.
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
DIR="$(cd "$(dirname "$0")" && pwd)"
USB="$(cd "$DIR/.." && pwd)"
PKG="$DIR/nvidia/nullmoth-nvidia-3.1.tar.gz"
PKG_SHA=e59b3183c53c9946fd123613bb06536a4a5c587120cb5383e62db6f1f672e4a1   # release v3.1, checked 26 Nov
WXG="$USB/WhateverXe-Graphics-0.4.4.pkg"                                       # needed by 03-remove-nullmoth.sh
WXG_SHA=f4c2d680a7c52c33a3f038ce6945da0aa2cc044e62b935a52ea046c7c473cfec
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
NEED="com.nullmoth.NVRM com.nullmoth.NVAccel com.nullmoth.NVRMFB com.nullmoth.NVRMAGDC"
die() { echo "STOP: $*"; exit 1; }
need_root() { [ "$(id -u)" = 0 ] || die "run it with sudo (see the first lines of this file)"; }
in_maintenance() { case " $(sysctl -n kern.bootargs 2>/dev/null) " in *" nvfb=1 "*) die "this runs in MAINTENANCE, not in NVIDIA mode (BIOS graphics Hybrid, G15-SWITCH-MODE.bat -> 2)";; *" -wexoff "*) ;; *) die "start in MAINTENANCE first (G15-SWITCH-MODE.bat -> 2, BIOS graphics Hybrid)";; esac; }
in_kc() { kmutil inspect -a x86_64 -A "$KC" 2>/dev/null | grep -oE 'com\.nullmoth\.[A-Za-z0-9]+|org\.hackintosh\.experimental\.NVPrimarySelector' | sort -u; }
sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }

case "${1:-}" in
check)
  echo "=== G15 NVIDIA mode check $(date) ==="
  echo "macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))   boot-args: $(nvram boot-args 2>/dev/null | cut -f2-)"
  echo "SIP (csr-active-config): $(nvram csr-active-config 2>/dev/null | cut -f2-)"
  case " $(sysctl -n kern.bootargs 2>/dev/null) " in
    *" nvfb=1 "*) echo "MODE: NVIDIA (NullMoth allowed to start)";;
    *" -wexoff "*) echo "MODE: MAINTENANCE (WhateverXe off; NullMoth parked by -nvoff)";;
    *" -nvoff "*) echo "MODE: an Iris Xe mode (NullMoth parked by -nvoff)";;
    *) echo "MODE: unknown - tell Claude";;
  esac
  echo "NVIDIA functions on PCI: $(ioreg -r -c IOPCIDevice -d 1 2>/dev/null | grep -c '"vendor-id" = <de100000>')   Iris Xe (46A6) on PCI: $(ioreg -r -c IOPCIDevice -d 1 2>/dev/null | grep -c '"device-id" = <a6460000>')"
  echo "NullMoth installed: $(cat /Library/NullMoth/driver-version 2>/dev/null || echo no)"
  if [ -f /Library/NullMoth/driver-version ]; then
    K=$(in_kc); echo "NullMoth kexts in the kernel collection:"; echo "${K:-(none)}" | sed 's/^/  /'
    miss=""; for id in $NEED; do printf '%s\n' "$K" | grep -qx "$id" || miss="$miss $id"; done
    [ -z "$miss" ] && echo "READY for the NVIDIA start: yes" || echo "READY for the NVIDIA start: NO (missing:$miss) - Privacy & Security > Allow, restart, check again"
  fi
  echo "NullMoth kexts running now (Iris Xe modes: want none; NVIDIA mode: NVRM, NVAccel, NVRMFB, NVRMAGDC, usually NMXAudio):"
  kmutil showloaded --list-only 2>/dev/null | grep -i nullmoth | sed 's/^/  /'
  echo "NullMoth guard: nv-starts=$(nvram 7C436110-AB2A-4BBB-A880-FE41995C9F82:nullmoth-nv-starts 2>/dev/null | cut -f2) nv-ok=$(nvram 7C436110-AB2A-4BBB-A880-FE41995C9F82:nullmoth-nv-ok 2>/dev/null | cut -f2)  debug.nvaccelfb=$(sysctl -n debug.nvaccelfb 2>/dev/null)"
  echo "Rollback package on the USB: $([ "$(sha "$WXG")" = "$WXG_SHA" ] && echo "OK" || echo "MISSING - tell Claude")"
  echo "--- displays"; system_profiler SPDisplaysDataType 2>/dev/null | grep -E 'Chipset Model|VRAM|Metal|Resolution|UI Looks like|Display Type|Connection Type|Main Display'
  ;;
nullmoth)
  need_root; in_maintenance
  [ -f /Library/NullMoth/driver-version ] && die "NullMoth $(cat /Library/NullMoth/driver-version) is already installed. To start over: sudo bash $DIR/15-nvidia-lab.sh remove"
  ioreg -r -c IOPCIDevice -d 1 2>/dev/null | grep -q '"vendor-id" = <de100000>' || die "macOS does not see the RTX 3050 - set the BIOS graphics to Hybrid and use MAINTENANCE (not D)"
  [ "$(sha "$WXG")" = "$WXG_SHA" ] || die "the rollback package $WXG is missing or changed; it is needed to undo this. Nothing was changed."
  [ -f "$PKG" ] || die "$PKG not found on the USB"
  [ "$(sha "$PKG")" = "$PKG_SHA" ] || die "the NullMoth package on the USB is not the verified 3.1 file"
  mkdir -p "$DIR/reports"; R="$DIR/reports/nullmoth-before-$(date +%Y%m%d-%H%M%S).txt"
  { echo "=== before NullMoth install $(date) ==="; sw_vers; echo "boot-args: $(nvram boot-args | cut -f2-)"; echo "--- /Library/Extensions"; ls -la /Library/Extensions
    echo "--- /Library/GPUBundles"; ls -la /Library/GPUBundles; echo "--- receipts"; pkgutil --pkgs | grep -iE 'whateverxe|nullmoth'
    echo "--- aux kernel collection"; kmutil inspect -a x86_64 -A "$KC" 2>/dev/null | grep -oE '[a-z]+\.[A-Za-z0-9.-]+\.[A-Za-z0-9.-]+' | sort -u; } > "$R" 2>&1
  sync; echo "Saved the before-state: $R"
  T=/private/tmp/nullmoth-3.1; rm -rf "$T"; mkdir -p "$T"
  tar -xzf "$PKG" -C "$T" || die "could not unpack the package"
  cd "$T/pkgroot" || die "unexpected package layout"
  BAD=$(shasum -a 256 -c SHA256SUMS 2>&1 | grep -v ': OK$')
  [ -z "$BAD" ] || die "package check failed: $BAD"
  echo "Package verified ($(grep -c . SHA256SUMS) files OK). Running NullMoth's own installer (needs internet for NVIDIA's firmware, about 550 MB)..."
  echo "(Its notes about missing boot-args are expected: mode 9 sets them.)"
  ./install.sh || die "NullMoth's installer stopped - take a photo of the last lines for Claude"
  echo "DONE. Now: Apple menu > Restart (MAINTENANCE again). After the restart: System Settings > Privacy & Security >"
  echo "Allow (if it is offered), then restart once more. Then: bash $DIR/15-nvidia-lab.sh check   (want READY: yes)"
  ;;
remove)
  need_root; in_maintenance
  echo "Removing NullMoth with the same script that cleaned this Mac on 19 Nov (it reinstalls WhateverXe Graphics 0.4.4"
  echo "so the kernel collection is rebuilt without NullMoth)..."
  bash "$DIR/03-remove-nullmoth.sh"
  ;;
*) sed -n '2,8p' "$0"; exit 1;;
esac
