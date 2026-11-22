# Credits and sources

The binaries in `EFI/` are unmodified upstream builds (tagged releases or Dortania build-repo CI builds), except
`itlwm.kext`, `XHCI-unsupported.kext` and the test build `WhateverXe-noccs.kext` (see the table). Licenses are those
of each upstream project; see the links.

Verified by hash against the official GitHub releases on 2026-11-19:
WhateverXe 0.8.2 and 0.8.3, AMFIAnchor 0.1.2 (and `AMFIAnchorInjector.kext` at tag 0.1.2), and AMFIPass 1.4.1 Mod.

| Component | Version | Source |
|---|---|---|
| OpenCore (BOOTx64.efi, OpenCore.efi, OpenCanopy, OpenRuntime, ResetNvramEntry) | 1.0.9 debug build (DBG-109-2026-11-08), identical to Dortania build-repo `OpenCorePkg-ebea824` | https://github.com/acidanthera/OpenCorePkg |
| HfsPlus.efi, apfs_aligned.efi | Apple file system drivers | https://github.com/acidanthera/OcBinaryData |
| Lilu | 1.7.3 | https://github.com/acidanthera/Lilu |
| WhateverXe (`WhateverXe.kext`) | 0.8.3 | https://github.com/b00t0x/WhateverXe |
| WhateverXe (`WhateverXe-0.8.2.kext`, used by configs B and C) | 0.8.2 | https://github.com/b00t0x/WhateverXe |
| WhateverXe test build (`WhateverXe-noccs.kext`, used only by the two `-noccs` test configs) | 0.8.3 + opt-in `-wex-noccs`, **not an official binary**. Upstream 0.8.3 plus a port of skmaiti2050's `-wex-noccs` patch (WhateverXe-TigerLakeH, branch `wex-0.8.2-noccs`; idea from [#163](https://github.com/b00t0x/WhateverXe/issues/163)). Built on 22 Nov 2026 by GitHub Actions ([run 45002111711](https://github.com/bharatvavdiya/WhateverXe/actions/runs/45002111711)) from commit `71e5c7c`. RELEASE executable SHA-256 `4e8b6d8c17049226db79fdf85ee35d6538aeede922bb186159baa2e27f5880a4`. A control build of unmodified 0.8.3 on the same CI matched the official binary except for its build-date stamp and Mach-O UUID | https://github.com/bharatvavdiya/WhateverXe (branch `wex-0.8.3-noccs`) |
| AMFIAnchor + AMFIAnchorInjector | 0.1.2 / 1.0.0 | https://github.com/b00t0x/AMFIAnchor |
| AMFIPass 1.4.1 Mod (used by config C only) | 1.4.1 | https://github.com/b00t0x/WhateverXe-Graphics (extras) |
| VirtualSMC + SMCProcessor, SMCSuperIO, SMCBatteryManager, SMCLightSensor, SMCDellSensors | 1.3.9 | https://github.com/acidanthera/VirtualSMC |
| RestrictEvents | 1.1.7 | https://github.com/acidanthera/RestrictEvents |
| NVMeFix | 1.1.4 | https://github.com/acidanthera/NVMeFix |
| BrightnessKeys | (release build) | https://github.com/acidanthera/BrightnessKeys |
| ECEnabler | 1.0.6 | https://github.com/1Revenger1/ECEnabler |
| CpuTopologyRebuild | 2.0.2 | https://github.com/b00t0x/CpuTopologyRebuild |
| VoodooPS2Controller | 2.3.8 | https://github.com/acidanthera/VoodooPS2 |
| VoodooI2C + VoodooI2CHID | 2.9.1 / 1.0 | https://github.com/VoodooI2C/VoodooI2C |
| itlwm | 2.3.0, **not the official binary**: SHA-256 `e4fd02a6…5bc`, while the official `itlwm_v2.3.0_stable.kext.zip` binary is `63952b0b…690b`. It can be swapped for the official one | https://github.com/OpenIntelWireless/itlwm |
| IntelBluetoothFirmware + IntelBTPatcher | 2.5.0, from the community fork that continues the project (official OpenIntelWireless releases stop at v2.4.0, 2024) | https://github.com/lshbluesky/IntelBluetoothFirmware (fork of https://github.com/OpenIntelWireless/IntelBluetoothFirmware) |
| BlueToolFixup | 2.7.3 | https://github.com/acidanthera/BrcmPatchRAM |
| RealtekRTL8111 | 2.4.2 | https://github.com/Mieze/RTL8111_driver_for_OS_X |
| USBToolBox + UTBDefault | (release build) / 1.0 | https://github.com/USBToolBox/kext |
| XHCI-unsupported | 0.9.2, **community variant**: 8 personalities including Alder Lake's `8086:51ED`, while RehabMan's upstream has 4 | https://github.com/RehabMan/OS-X-USB-Inject-All |

The ACPI tables (`SSDT-*.aml`) and ACPI patches were generated for this laptop. They are not generic.
`SSDT-dGPU-Off.aml` follows Dortania's SSDT-NoHybGfx method
(https://dortania.github.io/Getting-Started-With-ACPI/Laptops/laptop-disable.html), compiled with ACPICA `iasl`
from [`ACPI-source/SSDT-dGPU-Off.dsl`](ACPI-source/SSDT-dGPU-Off.dsl).

## Not included (download from the official source)

- **WhateverXe Graphics** package (`WhateverXe-Graphics-0.4.4.pkg`), installed inside macOS:
  https://github.com/b00t0x/WhateverXe-Graphics/releases
- Nothing from NullMoth / 1401 is included. Its NVIDIA driver needs settings (SIP `0xA43`, AMFI disabled)
  that conflicted with Intel Iris Xe acceleration on this laptop.
