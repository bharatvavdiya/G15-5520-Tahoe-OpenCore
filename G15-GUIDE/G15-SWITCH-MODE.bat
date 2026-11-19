@echo off
rem G15 5520: choose which OpenCore config the USB boots next. Run it in Windows by double-clicking.
rem It only copies one file inside this USB: EFI\OC\config-xxx.plist -> EFI\OC\config.plist
setlocal
set "OC=%~d0\EFI\OC"
if exist "%OC%\config-maintenance.plist" goto menu
echo Cannot find %OC%\config-maintenance.plist - run this file from the USB stick.
pause
exit /b 1
:menu
echo.
echo  G15 5520 - choose the next macOS start mode
echo  ------------------------------------------
echo   1  MAINTENANCE in Safe Mode  - WhateverXe off, no add-on kexts (repairs)
echo   2  MAINTENANCE normal        - WhateverXe off, slow but stable (use after a hang)
echo   3  A  - WhateverXe 0.8.3 + AMFIAnchor (official method, RECOMMENDED)
echo   4  D  - A + NVIDIA RTX 3050 turned off in macOS (test after A works)
echo   5  N  - WhateverXe 0.8.3 display only, no GPU acceleration (test)
echo   6  C  - old Nov 17 setup: WhateverXe 0.8.2 + AMFIPass Mod
echo   0  cancel
echo.
choice /c 1234560 /n /m "Type a number: "
if errorlevel 7 goto cancel
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
set "SRC=config-accel.plist"
set "NAME=A (WhateverXe 0.8.3 + AMFIAnchor)"
goto docopy
:pick4
set "SRC=config-accel-dgpuoff.plist"
set "NAME=D (A + NVIDIA dGPU off)"
goto docopy
:pick5
set "SRC=config-accel-noaccel.plist"
set "NAME=N (display only, no GPU acceleration)"
goto docopy
:pick6
set "SRC=config-accel-nov17.plist"
set "NAME=C (old Nov 17 setup)"
goto docopy
:docopy
rem No ( ) blocks here: mode names contain brackets, which would end such a block early.
if not exist "%OC%\%SRC%" goto notfound
copy /Y "%OC%\%SRC%" "%OC%\config.plist" >nul
fc /b "%OC%\%SRC%" "%OC%\config.plist" >nul
if errorlevel 1 goto copyfail
echo DONE: the next macOS start uses %NAME%.
pause
exit /b 0
:copyfail
echo STOP: the copy failed - ask Claude.
pause
exit /b 1
:notfound
echo STOP: %OC%\%SRC% not found. Nothing was changed.
pause
exit /b 1
