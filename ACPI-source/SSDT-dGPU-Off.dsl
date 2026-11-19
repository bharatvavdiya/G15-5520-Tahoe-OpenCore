/*
 * SSDT-dGPU-Off for Dell G15 5520 (BIOS 1.43.0), RTX 3050 Laptop 10DE:25E2 at \_SB.PC00.PEG1.PEGP
 * = PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0).
 *
 * Dortania "Bumblebee method" (SSDT-NoHybGfx), only the ACPI path changed, plus one CondRefOf guard.
 * Firmware path (SSDT "NvdTable"):
 *   PEGP._DSM(Optimus UUID, 0x100, 0x1A, {1,0,0,3}) -> NVOP: FLCH=1, OPCE=3 -> OMPR = 3
 *   PEGP._PS3 -> if OMPR == 3: \_SB.PC00.PGOF(1) -> L2/L3 entry, CLKREQ off, PERST# asserted, power GPIO off
 * PG01._OFF is NOT used: it is gated by OSYS > 0x07D9 and skipped while CMOS flag \NVFG == 1
 * (set by _PTS(4) on every Windows Fast Startup shutdown / hibernate).
 * Never call PG01._ON / NPON: NPON waits forever while the GPU does not answer on PCI.
 */
DefinitionBlock ("", "SSDT", 2, "DRTNIA", "NoHybGfx", 0x00000000)
{
    External (_SB_.PC00.PEG1.PEGP._DSM, MethodObj)    // 4 Arguments
    External (_SB_.PC00.PEG1.PEGP._PS3, MethodObj)    // 0 Arguments
    External (_SB_.PC00.PGOF, MethodObj)              // 1 Arguments, exists only when HGMD == 2

    Device (NHG1)
    {
        Name (_HID, "NHG10000")  // _HID: Hardware ID
        Method (_STA, 0, NotSerialized)  // _STA: Status
        {
            If (_OSI ("Darwin"))
            {
                Return (0x0F)
            }
            Else
            {
                Return (Zero)
            }
        }

        Method (_INI, 0, NotSerialized)  // _INI: Initialize
        {
            If (_OSI ("Darwin"))
            {
                If (CondRefOf (\_SB.PC00.PEG1.PEGP._DSM) && CondRefOf (\_SB.PC00.PEG1.PEGP._PS3) && CondRefOf (\_SB.PC00.PGOF))
                {
                    // Card Off Request (NVIDIA Optimus _DSM, function 0x1A)
                    \_SB.PC00.PEG1.PEGP._DSM (ToUUID ("a486d8f8-0bda-471b-a72b-6042a6b5bee0"), 0x0100, 0x1A, Buffer (0x04)
                        {
                             0x01, 0x00, 0x00, 0x03
                        })
                    // Card Off (D3cold through \_SB.PC00.PGOF)
                    \_SB.PC00.PEG1.PEGP._PS3 ()
                }
            }
        }
    }
}
