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
| Audio | Realtek ALC3254 on Intel HDA `8086:51C8` |
| SMBIOS | MacBookPro16,2 |

## Status

| Feature | Status |
|---|---|
| Boot, online-recovery install | Works |
| Ethernet | Works (used for the install) |
| Keyboard, trackpad | Work |
| Iris Xe acceleration | Metal 2 / 1536 MB reached on 26.7.3 (17 Nov, config C). On 19 Nov, after NullMoth was removed, config C no longer started the GPU, while config A (WhateverXe 0.8.3) had started it earlier that day. A is being retested on the clean system |
| Metal level | Metal 2, the level the Iris Xe driver provides. Metal 3 and Metal 4 are not possible: Metal 4 needs Apple silicon ([Apple, WWDC25](https://developer.apple.com/videos/play/wwdc2025/205/)), and Apple's [feature-set tables](https://developer.apple.com/metal/feature-sets) list Metal 3 only for UHD 630 / Iris Plus among Intel GPUs |
| Brightness | Worked together with acceleration (config C) |
| 120 Hz internal panel | Not verified in macOS yet |
| CPU | 12 cores (Hyper-Threading off), Apple power management (XCPM) active; 10-minute full-load test passed |
| Audio | Not working yet (no AppleALC) |
| Wi-Fi, Bluetooth | itlwm and IntelBluetoothFirmware included, not verified |
| Sleep | The firmware has no S3 (modern standby only); keep sleep off for now |
| NVIDIA RTX 3050 | No macOS driver exists for RTX 20/30/40 cards ([Dortania](https://dortania.github.io/GPU-Buyers-Guide/modern-gpus/nvidia-gpu.html)). Config D turns it off in macOS (not yet tested) |
| HDMI | Wired to the RTX 3050, so not usable in macOS |

## Configs (`EFI/OC`)

OpenCore only reads `config.plist`. The other files are ready-made variants. To switch, copy one over
`config.plist`; `G15-GUIDE/04-switch-to-accelerated.sh` (macOS) or `G15-GUIDE/G15-SWITCH-MODE.bat` (Windows)
does this for you.

| File | WhateverXe | AMFI | Purpose |
|---|---|---|---|
| `config-maintenance.plist` (same as `config.plist` here) | off (`-wexoff`) | AMFIAnchor, AMFI on | Installing macOS, maintenance |
| `config-accel.plist` (A) | 0.8.3 | AMFIAnchor + injector, AMFI on | **Recommended**: the official WhateverXe 0.8.3 setup |
| `config-accel-dgpuoff.plist` (D) | 0.8.3 | AMFIAnchor + injector, AMFI on | A + `SSDT-dGPU-Off.aml`: RTX 3050 powered off in macOS. Not yet tested |
| `config-accel-noaccel.plist` (N) | 0.8.3 with `-wex-noaccel` | AMFIAnchor | Diagnostic: display path without GPU acceleration |
| `config-accel-nov17.plist` (C) | 0.8.2 | AMFIPass 1.4.1 Mod + AMFI-relax boot-args | Old method; reached Metal 2 on 17 Nov, did not start the GPU on 19 Nov. WhateverXe now says to use AMFIAnchor instead |
| `config-accel-082.plist` (B) | 0.8.2 | AMFIAnchor + injector, AMFI on | Fallback |
| `config-maintenance-safe.plist` | off (`-wexoff`) + Safe Mode (`-x`) | AMFIAnchor | Clean boot without any add-on kexts, for repairs |
| `config-maintenance-ctr.plist` | off (`-wexoff`) | AMFIAnchor | Old maintenance with CpuTopologyRebuild on, kept only for comparison |

All configs:

- **SIP:** `csr-active-config` = `03080000` (0x803), as WhateverXe requires.
- **boot-args:** forced at every boot (listed in NVRAM > Delete).
- **Crashes:** the accelerated configs leave out `debug=0x100`, so a kernel panic reboots and OpenCore saves the
  panic log, instead of the screen just freezing.
- **Reset NVRAM:** runs with `--preserve-boot`, so it keeps Windows Boot Manager.
- **CpuTopologyRebuild:** off, together with its three "force HT" patches and `ctrsmt=full`. Its README lists
  "May cause random boot failure with verbose (`-v`) boot", and Hyper-Threading is off in this BIOS (12 threads),
  so it had little to do. ProvideCurrentCpuInfo and the Cpuid1Data spoof stay.
- **NullMoth flags:** NullMoth's self-repair NVRAM flags (`nullmoth-remove`, `-nv-starts`, `-nv-ok`, `-ws-loop`)
  are deleted at every boot.
- **`-nvoff`:** parks the NullMoth NVIDIA driver if one is installed, and does nothing otherwise.
- **`-v`:** verbose boot is on while testing.

Every component is an unmodified upstream release. The OpenCore files are identical to Dortania build
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
| `02-check.sh` | Collects version, kexts, display, logs and crash/GPU-restart reports into `reports/`. Changes nothing |
| `03-remove-nullmoth.sh` | Removes all NullMoth/1401 parts: services, kexts, Metal/Vulkan, NVRAM flags and the app. Then reinstalls WhateverXe Graphics 0.4.4 to rebuild the kernel collection |
| `04-switch-to-accelerated.sh` | Next boot = A (default), or D / N / C / B |
| `05-switch-to-maintenance.sh` | Next boot = maintenance (`safe` for Safe Mode, `ctr` for the old CpuTopologyRebuild variant) |
| `06-test-mode.sh` | Turns off sleep and display sleep, and Apple's media-analysis agents, for testing. `undo` reverts |
| `07-cpu-test.sh` | 10-minute CPU-only load test in maintenance mode. Logs every 30 s to `reports/` to catch a platform hang |
| `08-freeze-logs.sh` | After a freeze: saves the kernel, WindowServer and kext-manager logs of the last hours (default 4), the loaded kexts and the AuxKC contents to `reports/`. Changes nothing |
| `G15-SWITCH-MODE.bat` | The same mode switch from Windows, to recover after a freeze |

## Freeze notes

This is what is known, not a final verdict:

- **Without acceleration (7 MB):** the CPU draws everything, which gives heavy lag and long stalls under load.
- **A freeze where Caps Lock goes dead** is either a kernel panic hidden by `debug=0x100`, or a real hang.
- **GPU hangs on Gen12 Iris Xe** have been reported shortly after login, triggered by Apple's media-analysis
  compute work: [WhateverXe #163](https://github.com/b00t0x/WhateverXe/issues/163) and
  [#171](https://github.com/b00t0x/WhateverXe/issues/171).
- **Turning the display off and on** can hang a `46A6` laptop:
  [WhateverXe #117](https://github.com/b00t0x/WhateverXe/issues/117).
- **An identical i5-12500H / `46A6` setup** also reported freezes:
  [WhateverXe #42](https://github.com/b00t0x/WhateverXe/issues/42).
- **Untested hardware:** the WhateverXe README lists 80-EU Alder Lake-H graphics and Alder Lake-H internal
  screens as "expected to work, not yet tested on hardware".

What the logs showed on 19 Nov (macOS 26.7.3):

- **Config C (0.8.2), cleaned system:** the Intel driver stopped right after `Detecting Pre-Si/Si Mode`. It never
  published `IntelAccelerator`, and the screen fell back to the boot framebuffer (7 MB). The laptop then hung
  10 s after unlock, with no panic.
- **Config A (0.8.3), NullMoth still installed:** the GPU started fully (HWCAPS read, `IntelAccelerator`
  published, accelerated desktop). The hang came 9 s after login, when NullMoth's 1401 app launched while
  NullMoth's own `NMXGPU` Intel driver was loaded next to Apple's.

Log messages that are harmless on this laptop:

- `1 table load failures`: Dell's `xh_Dell_` SSDT refers to USB ports that the DSDT only creates inside a
  module-level `If`. macOS's older ACPI interpreter runs those blocks after all tables have loaded. USB still
  works through USBToolBox.
- `Kext com.apple.driver.IOVersatile ... failed to resolve library dependencies`: an Apple system kext that is not
  meant for this hardware. It appears in every boot, Safe Mode included.
- `AppleNVMe Assert failed` (twice at disk start-up), `kSMCKeyNotFound` from AppleSmartBatteryManager, and
  `Bad CPU type in executable` for Apple-silicon-only boot tasks.

## Credits

See [CREDITS.md](CREDITS.md). Every binary is an unmodified upstream release.

Provided as is, without warranty. Running macOS on non-Apple hardware may be against Apple's license terms.
