@echo off
rem G15 5520: choose which OpenCore config the USB boots next. Run it in Windows by double-clicking.
rem It only copies one file inside this USB: EFI\OC\config-xxx.plist -> EFI\OC\config.plist
setlocal
set "OC=%~d0\EFI\OC"
if not exist "%OC%\config-maintenance.plist" (
  echo Cannot find %OC%\config-maintenance.plist - run this file from the USB stick.
  pause
  exit /b 1
)
echo.
echo  G15 5520 - choose the next macOS start mode
echo  ------------------------------------------
echo   1  MAINTENANCE in Safe Mode  - WhateverXe off, no add-on kexts (use first / after a hang)
echo   2  MAINTENANCE normal        - WhateverXe off, slow but stable
echo   3  C  - Nov 17 setup: WhateverXe 0.8.2 + AMFIPass Mod (proven Metal 2)
echo   4  A  - WhateverXe 0.8.3 + AMFIAnchor
echo   5  B  - WhateverXe 0.8.2 + AMFIAnchor
echo   6  N  - WhateverXe 0.8.3 display only, no GPU acceleration (test)
echo   7  old MAINTENANCE with the CPU topology kext ON (only if Claude asks)
echo   0  cancel
echo.
choice /c 12345670 /n /m "Type a number: "
if errorlevel 8 goto cancel
if errorlevel 7 goto pick7
if errorlevel 6 goto pick6
if errorlevel 5 goto pick5
if errorlevel 4 goto pick4
if errorlevel 3 goto pick3
if errorlevel 2 goto pick2
if errorlevel 1 goto pick1
:cancel
echo Cancelled. Nothing was changed.
pause
exit /b 0
:pick1
set "SRC=config-maintenance-safe.plist"
set "NAME=MAINTENANCE in Safe Mode"
goto docopy
:pick2
set "SRC=config-maintenance.plist"
set "NAME=MAINTENANCE (normal)"
goto docopy
:pick3
set "SRC=config-accel-nov17.plist"
set "NAME=C (Nov 17 setup)"
goto docopy
:pick4
set "SRC=config-accel.plist"
set "NAME=A (WhateverXe 0.8.3 + AMFIAnchor)"
goto docopy
:pick5
set "SRC=config-accel-082.plist"
set "NAME=B (WhateverXe 0.8.2 + AMFIAnchor)"
goto docopy
:pick6
set "SRC=config-accel-noaccel.plist"
set "NAME=N (display only, no GPU acceleration)"
goto docopy
:pick7
set "SRC=config-maintenance-ctr.plist"
set "NAME=old MAINTENANCE with the CPU topology kext ON"
goto docopy
:docopy
copy /Y "%OC%\%SRC%" "%OC%\config.plist" >nul
fc /b "%OC%\%SRC%" "%OC%\config.plist" >nul
if errorlevel 1 (
  echo STOP: the copy failed - ask Claude.
) else (
  echo DONE: the next macOS start uses %NAME%.
)
pause
