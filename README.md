# G15-5520-Tahoe-OpenCore

OpenCore EFI for the **Dell G15 5520** running **macOS Tahoe (26.x)**, with Intel Iris Xe graphics through
[WhateverXe](https://github.com/b00t0x/WhateverXe).

> **Status: work in progress (November 2026).** macOS Tahoe boots and installs. Iris Xe Metal 2 acceleration
> has been reached on this laptop, but the setup is still being stabilized. Config A (the official WhateverXe 0.8.3
> method) is the one under test. See [Status](#status) and [Freeze notes](#freeze-notes).

## Hardware

| Part | Details |
|---|---|
| Laptop | Dell G15 5520, BIOS 1.43.0 (Hyper-Threading off in firmware: 12 threads) |
| CPU | Intel Core i5-12500H (Alder Lake-H) |
| iGPU | Intel Iris Xe `8086:46A6`, drives the internal 1920 x 1080 120 Hz panel |
| dGPU | NVIDIA RTX 3050 Laptop `10DE:25E2`, only wired to HDMI, not used by macOS |
| Storage | Samsung PM9B1 NVMe (dual boot with Windows 11) |
| Ethernet | Realtek RTL8111 |
| Audio | Realtek ALC236 (`10EC:0236`, subsystem `1028:0B64`) on Intel `8086:51C8` (Smart Sound mode); the built-in mic is an Intel SST digital mic |
| SMBIOS | MacBookPro16,2 |

## Status

| Feature | Status |
|---|---|
| Boot, online-recovery install | Works |
| Ethernet | Works (used for the install) |
| Keyboard, trackpad | Work |
| Iris Xe acceleration | **Works with config A** on the cleaned system (19 Nov, 26.7.3): Metal 2, 1536 MB, no GPU restarts (`recoveryCount` 0) in a ~26-minute session that ended normally. Longer tests (CPU/GPU load, video, display sleep) are still pending. Config C (0.8.2) no longer starts the GPU |
| Metal level | Metal 2, the level the Iris Xe driver provides. Metal 3 and Metal 4 are not possible: Metal 4 needs Apple silicon ([Apple, WWDC25](https://developer.apple.com/videos/play/wwdc2025/205/)), and Apple's [feature-set tables](https://developer.apple.com/metal/feature-sets) list Metal 3 only for UHD 630 / Iris Plus among Intel GPUs |
| Brightness | Worked together with acceleration (config C) |
| 120 Hz internal panel | Works: 1920 x 1080 @ 120.00 Hz (config A) |
| CPU | 12 cores (Hyper-Threading off), Apple power management (XCPM) active; 10-minute full-load test passed |
| Audio | Built-in speakers not possible for now: AppleALC needs AppleHDA, which macOS 26 removed ([AppleALC](https://github.com/acidanthera/AppleALC), [Dortania Tahoe notes](https://dortania.github.io/OpenCore-Install-Guide/extras/tahoe.html)). Use a class-compliant USB headset/DAC or Bluetooth audio. Planned as a separate test: VoodooHDA 3.7.1 (`VoodooHDA_BL`) injected by OpenCore, which leaves the AuxKC untouched. The built-in SST microphone and HDMI audio cannot work |
| Bluetooth | Firmware loads in normal boots (bluetoothd only loops in Safe Mode, where the kexts don't load); pairing not tested yet |
| Video | Hardware H.264 and HEVC decode; this driver stack has no VP9 or AV1 decoder ([#133](https://github.com/b00t0x/WhateverXe/issues/133)). **YouTube in Safari needs a selected sound output**: with none (the built-in speakers have no driver on Tahoe) Safari shows "An error occurred"; with a Bluetooth speaker selected it plays (confirmed 20 Nov). Chrome with Skia Graphite disabled is the fallback ([#130](https://github.com/b00t0x/WhateverXe/issues/130)). Avoid full-screen video and the AirPlay Receiver ([#129](https://github.com/b00t0x/WhateverXe/issues/129)) |
| Wi-Fi | Intel AX201 (`8086:51F0`, CNVi). The EFI loads the official itlwm 2.3.0; with the HeliPort 1.5.0 app it should give working Wi-Fi (shown as Ethernet, no AirDrop), being tested. Native Wi-Fi menu: ForbiddenItlwm (community beta, OpenCore-only) planned as a separate test. Never root-patch this Mac (OCLP / kgp AirportItlwm-Tahoe): it rebuilds the AuxKC that holds the Iris Xe kexts |
| Sleep | The firmware has no S3 (modern standby only); keep sleep off for now |
| NVIDIA RTX 3050 | No macOS driver exists for RTX 20/30/40 cards ([Dortania](https://dortania.github.io/GPU-Buyers-Guide/modern-gpus/nvidia-gpu.html)). Config D hides it from macOS (21 Nov: not enumerated). Whether it is also powered off is unproven (its PCIe port still reported an active link) and is being measured with `14-power-check.sh` |
| HDMI | Wired to the RTX 3050, so not usable in macOS |

## Configs (`EFI/OC`)

OpenCore only reads `config.plist`. The other files are ready-made variants. To switch, copy one over
`config.plist`; `G15-GUIDE/04-switch-to-accelerated.sh` (macOS) or `G15-GUIDE/G15-SWITCH-MODE.bat` (Windows)
does this for you.

| File | WhateverXe | AMFI | Purpose |
|---|---|---|---|
| `config-maintenance.plist` (same as `config.plist` here) | off (`-wexoff`) | AMFIAnchor, AMFI on | Installing macOS, maintenance |
| `config-accel.plist` (A) | 0.8.3 | AMFIAnchor + injector, AMFI on | **Recommended**: the official WhateverXe 0.8.3 setup |
| `config-accel-dgpuoff.plist` (D) | 0.8.3 | AMFIAnchor + injector, AMFI on | A + `SSDT-dGPU-Off.aml`: hides the RTX 3050 from macOS. First session (21 Nov) ran 41 min, then froze during a wallpaper change; being re-tested, see [Freeze notes](#freeze-notes) |
| `config-accel-noaccel.plist` (N) | 0.8.3 with `-wex-noaccel` | AMFIAnchor | Diagnostic: display path without GPU acceleration |
| `config-accel-nov17.plist` (C) | 0.8.2 | AMFIPass 1.4.1 Mod + AMFI-relax boot-args | Old method; reached Metal 2 on 17 Nov, did not start the GPU on 19 Nov. WhateverXe now says to use AMFIAnchor instead |
| `config-accel-082.plist` (B) | 0.8.2 | AMFIAnchor + injector, AMFI on | Fallback |
| `config-maintenance-safe.plist` | off (`-wexoff`) + Safe Mode (`-x`) | AMFIAnchor | Clean boot without any add-on kexts, for repairs |
| `config-maintenance-ctr.plist` | off (`-wexoff`) | AMFIAnchor | Old maintenance with CpuTopologyRebuild on, kept only for comparison |

All configs:

- **SIP:** `csr-active-config` = `03080000` (0x803), as WhateverXe requires.
- **boot-args:** forced at every boot (listed in NVRAM > Delete).
- **Crashes:** the accelerated configs leave out `debug=0x100`, so a kernel panic reboots instead of the screen just
  freezing. After a panic, macOS keeps a `Kernel-*.panic` report and the next OpenCore log shows `AAPL: #[EB|P:MPI] Y`.
  OpenCore's own `panic-*.txt` stayed empty on this laptop even after a real panic.
- **Reset NVRAM:** runs with `--preserve-boot`, so it keeps Windows Boot Manager.
- **CpuTopologyRebuild:** off, together with its three "force HT" patches and `ctrsmt=full`. Its README lists
  "May cause random boot failure with verbose (`-v`) boot", and Hyper-Threading is off in this BIOS (12 threads),
  so it had little to do. ProvideCurrentCpuInfo and the Cpuid1Data spoof stay.
- **NullMoth flags:** NullMoth's self-repair NVRAM flags (`nullmoth-remove`, `-nv-starts`, `-nv-ok`, `-ws-loop`)
  are deleted at every boot.
- **`-nvoff`:** parks the NullMoth NVIDIA driver if one is installed, and does nothing otherwise.
- **`-v`:** verbose boot is on while testing.

The components are unmodified upstream builds (tagged releases or Dortania build-repo CI builds), with two
exceptions listed in [CREDITS.md](CREDITS.md): `XHCI-unsupported.kext` is a community variant that adds Alder Lake's
`8086:51ED`, and `itlwm.kext` is not the official v2.3.0 binary. The OpenCore files are identical to Dortania build
`OpenCorePkg-ebea824` (1.0.9), and all configs pass that build's `ocvalidate`.

### `SSDT-dGPU-Off.aml` (config D only)

Source: [`ACPI-source/SSDT-dGPU-Off.dsl`](ACPI-source/SSDT-dGPU-Off.dsl). It is Dortania's
[SSDT-NoHybGfx](https://dortania.github.io/Getting-Started-With-ACPI/Laptops/laptop-disable.html) method with this
laptop's path, `\_SB.PC00.PEG1.PEGP`. At start-up it calls the NVIDIA Optimus `_DSM` (function `0x1A`, which only sets
the power-off flag) and then `_PS3`, which runs the firmware's own `PGOF` power-off. Every wait in that path is
bounded. It acts only in macOS (`_OSI("Darwin")`); Windows does not boot through OpenCore anyway.

## Using it

1. **Generate your own SMBIOS** (MacBookPro16,2) with [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS). Fill
   `SystemSerialNumber`, `MLB`, `SystemUUID` and `ROM` under `PlatformInfo > Generic` in every config you use.
   This repo only contains placeholders.
2. Copy `EFI` (and `G15-GUIDE`) to a FAT32 USB drive. In the BIOS, disable Secure Boot.
3. Install macOS Tahoe **26.7 or later**. The graphics package below refuses older versions, and does not support macOS 27.
4. In macOS, install **WhateverXe Graphics 0.4.4** from the
   [official releases](https://github.com/b00t0x/WhateverXe-Graphics/releases), then switch to an accelerated
   config and restart.

**Do not use 1401 / NullMoth on the same macOS install.** Its NVIDIA driver forces SIP `0xA43` and AMFI-off
boot-args, and its "GPU test" driver (`nmxintel`) takes over the Iris Xe. On this laptop that combination
gave 7 MB VRAM and freezes. `G15-GUIDE/03-remove-nullmoth.sh` removes everything it installs.

## Guide and scripts (`G15-GUIDE/`)

Paths in the scripts assume the USB is mounted as `/Volumes/1401`; the scripts also work from any other volume.

| File | What it does |
|---|---|
| `01-STEPS.txt` | Step-by-step test plan |
| `02-check.sh` | Collects version, kexts, display, logs and crash/GPU-restart reports into `reports/`, and shows whether a moving-wallpaper or video-decoder process runs and the Mac's IP address (for a ping test during a freeze). Changes nothing |
| `03-remove-nullmoth.sh` | Removes all NullMoth/1401 parts: services, kexts, Metal/Vulkan, NVRAM flags and the app. Then reinstalls WhateverXe Graphics 0.4.4 to rebuild the kernel collection |
| `04-switch-to-accelerated.sh` | Next boot = A (default), or D / N / C / B |
| `05-switch-to-maintenance.sh` | Next boot = maintenance (`safe` for Safe Mode, `ctr` for the old CpuTopologyRebuild variant) |
| `06-test-mode.sh` | Turns off sleep and display sleep, and Apple's media-analysis agents. These are the safe daily settings for this laptop, so there is deliberately no `undo` |
| `07-cpu-test.sh` | 10-minute CPU load test (works in every mode; the steps run it in mode A). Logs every 30 s to `reports/` to catch a platform hang |
| `08-freeze-logs.sh` | After a freeze: saves the kernel, WindowServer and kext-manager logs of the last hours (default 12; the steps use 24), every process's log for the 10 minutes before the previous macOS session stopped, the loaded kexts and the AuxKC contents to `reports/`. Changes nothing |
| `09-perf-check.sh` | Performance check, run with `sudo`: `quick`, `watch` (samples while you open an app) or no word for the full check (adds battery, `powermetrics` and a 10 s CPU load). Writes `reports/perf-*.txt`. Changes nothing |
| `10-video-log.sh` | Read-only video check, run without `sudo` right after a video error: sound devices macOS sees, recent WebKit / video decoder / WindowServer crash reports and the media log lines of the last 10 minutes |
| `10-youtube-test.txt` | Steps plus one line to paste into Safari's JavaScript console: prints which codecs Safari offers, YouTube's player error and the clock offset. Only reads |
| `11-frame-test.html` | Local frame-rate test from [WhateverXe #130](https://github.com/b00t0x/WhateverXe/issues/130): canvas/WebGL Hz in Chrome and Safari, to see whether the 100 ms GPU completion stall happens on this laptop. No network, changes nothing |
| `12-lab-check.sh` | Read-only: APFS free space, this install's volume-group IDs and the macOS installers Apple offers, to plan a separate second macOS (NVIDIA lab). Run without `sudo` |
| `13-log-window.sh` | Read-only, run with `sudo`: saves the full log (all processes) of one time window to `reports/`. Default = the 21 Nov freeze window |
| `14-power-check.sh` | Read-only, no `sudo`: average battery power over 2 minutes (charger unplugged), to compare mode D with mode A |
| `G15-SWITCH-MODE.bat` | The same mode switch from Windows, to recover after a freeze |
| `G15-CHECK-USB.cmd` | Windows: runs `chkdsk /f /x` on the USB labelled `1401` (it needs that label) and shows which config the next start uses. The steps expect it at the USB root |

## Freeze notes

This is what is known, not a final verdict:

- **Without acceleration (7 MB):** the CPU draws everything, which gives heavy lag and long stalls under load.
- **A freeze where Caps Lock goes dead** is a kernel panic hidden by `debug=0x100`, a real hang, or a
  WindowServer/GPU stall: on Tahoe the keyboard's HID event filters (Caps Lock included) run inside WindowServer.
  A ping from another device during the freeze tells whether the kernel is still alive.
- **GPU hangs on Gen12 Iris Xe** have been reported shortly after login, triggered by Apple's media-analysis
  compute work: [WhateverXe #163](https://github.com/b00t0x/WhateverXe/issues/163) and
  [#171](https://github.com/b00t0x/WhateverXe/issues/171).
- **Turning the display off and on** hung other `46A6` laptops on older WhateverXe builds (comments in
  [#117](https://github.com/b00t0x/WhateverXe/issues/117) and [#90](https://github.com/b00t0x/WhateverXe/issues/90)).
  0.8.3 claims better eDP handling after display sleep, but it is untested on this panel, so display sleep stays off.
- **An identical i5-12500H / `46A6` setup** also reported freezes:
  [WhateverXe #42](https://github.com/b00t0x/WhateverXe/issues/42).
- **Untested hardware:** the WhateverXe README lists 80-EU Alder Lake-H graphics and Alder Lake-H internal
  screens as "expected to work, not yet tested on hardware".

What the logs showed on 19 Nov (macOS 26.7.3):

- **The only real kernel panic (14:29, NullMoth-era setup):** `/usr/sbin/sysctl` hit a general-protection fault
  in `strcmp` while XNU looked up a sysctl name that pointed into an unloaded Aux kernel collection kext. NullMoth's
  NVIDIA/Intel kexts register `debug.*` sysctls without unregistering them, so they are the most likely owners
  (strong inference, not proof). With `debug=0x100` the Mac halted instead of rebooting, so it looked like a freeze.
  It cannot recur in A or D: NullMoth is gone and `debug=0x100` is no longer used.
- **Config A on the cleaned system (21:44):** Metal 2, 1536 MB, 120 Hz, `recoveryCount` 0, no GPU restart, link or
  backlight errors, and an orderly shutdown after about 26 minutes.

- **Config C (0.8.2), cleaned system:** the Intel driver stopped right after `Detecting Pre-Si/Si Mode`. It never
  published `IntelAccelerator`, and the screen fell back to the boot framebuffer (7 MB). The laptop then hung
  10 s after unlock, with no panic.
- **Config A (0.8.3), NullMoth still installed:** the GPU started fully (HWCAPS read, `IntelAccelerator`
  published, accelerated desktop). The hang came 9 s after login, when NullMoth's 1401 app launched while
  NullMoth's own `NMXGPU` Intel driver was loaded next to Apple's.

What the logs showed on 21 Nov (config D, first session):

- D hid the RTX 3050 as designed (not enumerated on the PCI bus; present again in maintenance), and the session
  ran 41 minutes normally, including a performance watch with healthy GPU readings.
- The whole Mac then froze while the wallpaper was changed in System Settings (Tahoe Dark, then a plain colour).
  The unified log simply stops at 17:17:37 IST; there is no GPU error, hang or restart line, and OpenCore's
  next log shows `EB|P:MPI] N` (no panic). The forced power-off also cut off the last seconds of the log.
- Most likely cause: the Iris Xe driver stalling during wallpaper work. The Tahoe wallpaper (its renderer is
  Apple's `NeptuneOneWallpaper` extension) ran with acceleration for the first time in that session, and it
  started the video decoder (`VTDecoderXPCService`), which also decodes HEIC stills. Mode A logged GPU "timed out
  fence" stalls during video decoding too. Because the new wallpaper and the new SSDT arrived together, D is not
  ruled out. No upstream WhateverXe report covers wallpaper-change hangs; GPU hangs under video work on this
  chip family are reported ([#75](https://github.com/b00t0x/WhateverXe/issues/75),
  [#126](https://github.com/b00t0x/WhateverXe/issues/126), [#168](https://github.com/b00t0x/WhateverXe/issues/168)).
- Workaround: a plain colour wallpaper and a non-video screen saver, changed only in maintenance mode.
- Separate issue: about 2 minutes after every start, macOS's NetBIOS service (`netbiosd`) opens an SMB
  connection to a device on the local network by itself; nothing is mounted. At shutdown the SMB code can loop on
  reconnecting (about 560,000 kernel log lines in under a second) and stall the shutdown (20 and 22 Nov). This is
  not a graphics freeze, and the guide handles it separately.

Log messages that are harmless on this laptop:

- `1 table load failures`: Dell's `xh_Dell_` SSDT refers to USB ports that the DSDT only creates inside a
  module-level `If`. macOS's older ACPI interpreter runs those blocks after all tables have loaded. USB still
  works through USBToolBox.
- `Kext com.apple.driver.IOVersatile ... failed to resolve library dependencies`: an Apple system kext that is not
  meant for this hardware. It appears in every boot, Safe Mode included.
- `AppleNVMe Assert failed` (twice at disk start-up), `kSMCKeyNotFound` from AppleSmartBatteryManager, and
  `Bad CPU type in executable` for Apple-silicon-only boot tasks.

## Credits

See [CREDITS.md](CREDITS.md). The binaries are unmodified upstream builds, except the two noted there.

Provided as is, without warranty. Running macOS on non-Apple hardware may be against Apple's license terms.
