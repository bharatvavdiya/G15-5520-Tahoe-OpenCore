# G15-5520-Tahoe-OpenCore

OpenCore EFI for the **Dell G15 5520** running **macOS Tahoe (26.x)**, with Intel Iris Xe graphics through
[WhateverXe](https://github.com/b00t0x/WhateverXe).

> **Status: work in progress (November 2026).** macOS Tahoe boots and installs. Iris Xe Metal acceleration
> has been reached once (config C, macOS 26.7.3), but it is not stable yet. See [Status](#status).

## Hardware

| Part | Details |
|---|---|
| Laptop | Dell G15 5520, BIOS 1.43.0 |
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
| Iris Xe acceleration | Config C reached Metal 2 / 1536 MB once on 26.7.3. Config A (WhateverXe 0.8.3) reaches an accelerated desktop, then freezes. Under investigation |
| Brightness | Worked together with acceleration (config C) |
| 120 Hz internal panel | Not verified in macOS yet |
| Audio | Not working yet (no AppleALC) |
| Wi-Fi, Bluetooth | itlwm and IntelBluetoothFirmware included, not verified |
| Sleep | Not verified |
| NVIDIA RTX 3050 | Not used |

## Configs (`EFI/OC`)

OpenCore only reads `config.plist`. The other files are ready-made variants. To switch, copy one over
`config.plist` (the scripts in `G15-GUIDE/` do this for you).

| File | WhateverXe | AMFI | Purpose |
|---|---|---|---|
| `config-maintenance.plist` (same as `config.plist` here) | off (`-wexoff`) | AMFIAnchor, AMFI on | Installing macOS, maintenance, stable |
| `config-accel.plist` (A) | 0.8.3 | AMFIAnchor + injector, AMFI on | Official WhateverXe 0.8.3 setup |
| `config-accel-082.plist` (B) | 0.8.2 | AMFIAnchor + injector, AMFI on | Fallback |
| `config-accel-nov17.plist` (C) | 0.8.2 | AMFIPass 1.4.1 Mod + AMFI-relax boot-args | The setup that reached Metal 2 |

All configs:

- **SIP:** `csr-active-config` = `03080000` (0x803), as WhateverXe requires.
- **boot-args:** forced at every boot (listed in NVRAM > Delete).
- **`-nvoff`:** parks the NullMoth NVIDIA driver if one is installed, and does nothing otherwise.
- **`-v`:** verbose boot is on.
- **`PollAppleHotKeys`:** on, so Shift+Enter on the macOS entry boots Safe Mode.

## Using it

1. **Generate your own SMBIOS** (MacBookPro16,2) with [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS). Fill
   `SystemSerialNumber`, `MLB`, `SystemUUID` and `ROM` under `PlatformInfo > Generic` in every config you use.
   This repo only contains placeholders.
2. Copy `EFI` to a FAT32 USB drive. In the BIOS, disable Secure Boot.
3. Install macOS Tahoe **26.7 or later**. The graphics package below refuses older versions, and does not support macOS 27.
4. In macOS, install **WhateverXe Graphics 0.4.4** from the
   [official releases](https://github.com/b00t0x/WhateverXe-Graphics/releases), then switch `config.plist` to
   an accelerated config and restart.

**Do not use 1401 / NullMoth on the same macOS install.** Its NVIDIA driver forces SIP `0xA43` and AMFI-off
boot-args, and its "GPU test" driver (`nmxintel`) takes over the Iris Xe. On this laptop that combination
gave 7 MB VRAM and freezes.

## Credits

See [CREDITS.md](CREDITS.md). Every binary is an unmodified upstream release.

Provided as is, without warranty. Running macOS on non-Apple hardware may be against Apple's license terms.
