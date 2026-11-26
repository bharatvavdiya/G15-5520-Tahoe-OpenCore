#!/bin/bash
# G15 NVIDIA mode: a second macOS on the internal disk (volume "NVIDIA") that runs the NullMoth 3.1 driver on the
# RTX 3050 while the BIOS sends the screen to the NVIDIA card. Your normal macOS ("macintosh") is never changed.
#   bash      /Volumes/1401/G15-GUIDE/15-nvidia-lab.sh check       (read-only status; works in every mode)
#   sudo bash /Volumes/1401/G15-GUIDE/15-nvidia-lab.sh volume      (on "macintosh": add the empty APFS volume NVIDIA)
#   sudo bash /Volumes/1401/G15-GUIDE/15-nvidia-lab.sh installer   (on "macintosh": download the macOS 26.7.3 installer)
#   bash      /Volumes/1401/G15-GUIDE/15-nvidia-lab.sh install     (on "macintosh": checks, then opens Apple's installer)
#   sudo bash /Volumes/1401/G15-GUIDE/15-nvidia-lab.sh nullmoth    (on "NVIDIA" only: install the verified NullMoth 3.1)
#   sudo bash /Volumes/1401/G15-GUIDE/15-nvidia-lab.sh hide        (on "macintosh": hide it from the NVIDIA mode menu)
#   sudo bash /Volumes/1401/G15-GUIDE/15-nvidia-lab.sh unhide      (on "macintosh": undo hide)
# Never use the 1401 app: it rewrites the OpenCore config on this USB.
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
DIR="$(cd "$(dirname "$0")" && pwd)"
LAB=NVIDIA
MAIN=macintosh
VERSION=26.7.3
APP="/Applications/Install macOS Tahoe.app"
PKG="$DIR/nvidia/nullmoth-nvidia-3.1.tar.gz"
PKG_SHA=e59b3183c53c9946fd123613bb06536a4a5c587120cb5383e62db6f1f672e4a1   # release v3.1, checked 26 Nov
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
NEED="com.nullmoth.NVRM com.nullmoth.NVAccel com.nullmoth.NVRMFB com.nullmoth.NVRMAGDC"
HIDE="OCN:Disabled"   # hides this macOS only from OpenCore configs with InstanceIdentifier OCN (= config-nvidia)
die() { echo "STOP: $*"; exit 1; }
need_root() { [ "$(id -u)" = 0 ] || die "run it with sudo (see the first lines of this file)"; }
plist() { plutil -extract "$2" raw -o - - 2>/dev/null <<EOF
$1
EOF
}
INFO=$(diskutil info -plist / 2>/dev/null)
BOOTVOL=$(plist "$INFO" VolumeName)
CONT=$(plist "$INFO" APFSContainerReference)
GROUP=$(plist "$INFO" APFSVolumeGroupID)
PREBOOT="/System/Volumes/Preboot/$GROUP"
lab_exists() { diskutil apfs list "$CONT" 2>/dev/null | grep -Eq "Name: +$LAB \("; }
on_main() { [ "$BOOTVOL" = "$MAIN" ] || die "this step runs only on your normal macOS \"$MAIN\" (now: \"$BOOTVOL\")"; }
free_gb() { df -k / | awk 'NR==2 { print int($4 / 1048576) }'; }
# macOS version inside the installer app (read-only mount of its SharedSupport.dmg); empty if it cannot be read
installer_version() {
  local dmg="$APP/Contents/SharedSupport/SharedSupport.dmg" mp v=""
  [ -f "$dmg" ] || return 0
  mp=$(hdiutil attach -nobrowse -readonly -noverify "$dmg" 2>/dev/null | awk -F'\t' '/\/Volumes\// { print $NF; exit }')
  [ -n "$mp" ] || return 0
  v=$(plutil -extract Assets.0.OSVersion raw -o - "$mp/com_apple_MobileAsset_MacSoftwareUpdate/com_apple_MobileAsset_MacSoftwareUpdate.xml" 2>/dev/null)
  hdiutil detach -quiet "$mp" 2>/dev/null
  echo "$v"
}
in_kc() { kmutil inspect -a x86_64 -A "$KC" 2>/dev/null | grep -oE 'com\.nullmoth\.[A-Za-z0-9]+|org\.hackintosh\.experimental\.NVPrimarySelector' | sort -u; }

case "${1:-}" in
check)
  echo "=== G15 NVIDIA mode check $(date) ==="
  echo "Started from volume: $BOOTVOL  (container $CONT)   macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  echo "boot-args: $(nvram boot-args 2>/dev/null | cut -f2-)"
  echo "SIP (csr-active-config): $(nvram csr-active-config 2>/dev/null | cut -f2-)"
  case " $(sysctl -n kern.bootargs 2>/dev/null) " in
    *" nvfb=1 "*) echo "MODE: NVIDIA (NullMoth driver allowed to start)";;
    *" -wexoff "*) echo "MODE: MAINTENANCE (WhateverXe off; NullMoth stays parked)";;
    *) echo "MODE: an Intel mode";;
  esac
  echo "Volume $LAB in this container: $(lab_exists && echo yes || echo no)    Free space: $(free_gb) GB"
  [ -d "$APP" ] && echo "Installer: present" || echo "Installer: not downloaded"
  echo "NVIDIA functions on PCI: $(ioreg -r -c IOPCIDevice -d 1 2>/dev/null | grep -c '"vendor-id" = <de100000>')   Iris Xe (46A6) on PCI: $(ioreg -r -c IOPCIDevice -d 1 2>/dev/null | grep -c '"device-id" = <a6460000>')"
  if [ "$BOOTVOL" = "$MAIN" ]; then
    v=$(cat "$PREBOOT/.contentVisibility" 2>/dev/null)
    echo "\"$MAIN\" hidden from the NVIDIA mode menu: $([ "$v" = "$HIDE" ] && echo yes || echo "no${v:+ (file says: $v)}")"
  fi
  echo "NullMoth installed on this volume: $(cat /Library/NullMoth/driver-version 2>/dev/null || echo no)"
  if [ -f /Library/NullMoth/driver-version ]; then
    K=$(in_kc); echo "NullMoth kexts in this volume's kernel collection:"; echo "${K:-  (none)}" | sed 's/^/  /'
    miss=""; for id in $NEED; do printf '%s\n' "$K" | grep -qx "$id" || miss="$miss $id"; done
    [ -z "$miss" ] && echo "READY for the NVIDIA start: yes" || echo "READY for the NVIDIA start: NO (missing:$miss) - allow them in Privacy & Security and restart, or tell Claude"
  fi
  echo "NullMoth kexts loaded now (NVIDIA mode wants NVRM, NVAccel, NVRMFB, NVRMAGDC, usually NMXAudio too):"; kmutil showloaded --list-only 2>/dev/null | grep -i nullmoth | sed 's/^/  /'
  echo "NullMoth guard: nv-starts=$(nvram 7C436110-AB2A-4BBB-A880-FE41995C9F82:nullmoth-nv-starts 2>/dev/null | cut -f2) nv-ok=$(nvram 7C436110-AB2A-4BBB-A880-FE41995C9F82:nullmoth-nv-ok 2>/dev/null | cut -f2)  debug.nvaccelfb=$(sysctl -n debug.nvaccelfb 2>/dev/null)"
  echo "--- displays"; system_profiler SPDisplaysDataType 2>/dev/null | grep -E 'Chipset Model|VRAM|Metal|Resolution|UI Looks like|Display Type|Connection Type|Main Display'
  ;;
volume)
  need_root; on_main
  lab_exists && die "a volume named $LAB already exists - nothing to do"
  [ "$(free_gb)" -ge 60 ] || die "only $(free_gb) GB free in the container; NVIDIA mode needs at least 60 GB"
  echo "Adding an empty APFS volume \"$LAB\" to container $CONT (nothing existing is erased)..."
  diskutil apfs addVolume "$CONT" APFS "$LAB" || die "diskutil could not add the volume"
  diskutil apfs list "$CONT" | grep -E 'Name:|Capacity Not Allocated'
  echo "DONE. Next: sudo bash $DIR/15-nvidia-lab.sh installer"
  ;;
installer)
  need_root; on_main
  if [ ! -d "$APP" ]; then
    echo "Downloading the full macOS $VERSION installer from Apple (about 17 GB; keep the charger and Ethernet in)..."
    softwareupdate --fetch-full-installer --full-installer-version "$VERSION" || die "the download failed - run this again"
  fi
  [ -d "$APP" ] || die "$APP not found after the download"
  v=$(installer_version)
  if [ -n "$v" ] && [ "$v" != "$VERSION" ]; then die "$APP contains macOS $v, not $VERSION. Move it to the Trash and run this again"; fi
  echo "Installer: macOS ${v:-(version not readable, downloaded as $VERSION)}"
  [ "$(free_gb)" -ge 40 ] || die "only $(free_gb) GB free left; the install needs about 40 GB"
  echo "DONE. Next (when you have 1 hour): bash $DIR/15-nvidia-lab.sh install"
  ;;
install)
  on_main
  [ "$(id -u)" = 0 ] && die "run this one WITHOUT sudo (it opens Apple's installer for you)"
  lab_exists || die "no volume $LAB yet - run the volume step first"
  [ -d "/Volumes/$LAB" ] || die "/Volumes/$LAB is not mounted - open Disk Utility, select $LAB, click Mount, then run this again"
  [ "$(plist "$(diskutil info -plist "/Volumes/$LAB" 2>/dev/null)" APFSContainerReference)" = "$CONT" ] || die "/Volumes/$LAB is not in the same container as $MAIN"
  [ -d "/Volumes/$LAB/System" ] && die "/Volumes/$LAB already has macOS on it"
  [ -d "$APP" ] || die "installer missing - run the installer step first"
  [ "$(free_gb)" -ge 40 ] || die "only $(free_gb) GB free; the install needs about 40 GB"
  echo "Opening Apple's installer. In it: Continue > Agree > Agree > click \"Show All Disks...\" > select \"$LAB\""
  echo "(NOT \"$MAIN\") > Continue > your password. The Mac then restarts by itself several times: at every"
  echo "OpenCore menu choose \"macOS Installer\" (later \"$LAB\"), never \"$MAIN\", until the setup screens appear."
  open "$APP"
  ;;
nullmoth)
  need_root
  [ "$BOOTVOL" = "$LAB" ] || die "NullMoth goes ONLY on the volume $LAB (now started from \"$BOOTVOL\"). Nothing was changed."
  pkgutil --pkgs 2>/dev/null | grep -qi whateverxe && die "this volume has WhateverXe Graphics installed - it is not the NVIDIA volume"
  [ -f "$PKG" ] || die "$PKG not found on the USB"
  S=$(shasum -a 256 "$PKG" | cut -d' ' -f1)
  [ "$S" = "$PKG_SHA" ] || die "the NullMoth package on the USB is not the verified 3.1 file (sha256 $S)"
  T=/private/tmp/nullmoth-3.1; rm -rf "$T"; mkdir -p "$T"
  tar -xzf "$PKG" -C "$T" || die "could not unpack the package"
  cd "$T/pkgroot" || die "unexpected package layout"
  BAD=$(shasum -a 256 -c SHA256SUMS 2>&1 | grep -v ': OK$')
  [ -z "$BAD" ] || die "package check failed: $BAD"
  echo "Package verified ($(grep -c . SHA256SUMS) files OK). Running NullMoth's own installer (needs internet for NVIDIA's firmware, about 550 MB)..."
  ./install.sh || die "NullMoth's installer stopped - take a photo of the last lines for Claude"
  echo "DONE. Now: Apple menu > Restart and choose \"$LAB\". After the restart: System Settings > Privacy & Security >"
  echo "Allow (if it is offered), then restart once more. Then: bash $DIR/15-nvidia-lab.sh check  (want READY: yes)"
  ;;
hide)
  need_root; on_main
  [ -n "$GROUP" ] && [ -f "$PREBOOT/System/Library/CoreServices/boot.efi" ] || die "cannot find this macOS's Preboot folder ($PREBOOT)"
  printf '%s' "$HIDE" > "$PREBOOT/.contentVisibility" || die "could not write $PREBOOT/.contentVisibility"
  [ "$(cat "$PREBOOT/.contentVisibility")" = "$HIDE" ] || die "the file does not read back correctly"
  echo "DONE: \"$MAIN\" no longer appears in the OpenCore menu of the NVIDIA mode (mode 9). All other modes still show it."
  ;;
unhide)
  need_root; on_main
  rm -f "$PREBOOT/.contentVisibility" && echo "DONE: \"$MAIN\" shows in every OpenCore menu again."
  ;;
*) sed -n '2,11p' "$0"; exit 1;;
esac
