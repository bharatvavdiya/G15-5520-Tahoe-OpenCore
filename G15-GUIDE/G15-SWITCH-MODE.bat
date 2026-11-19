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
echo   1  MAINTENANCE  - WhateverXe off, slow but stable (use after a freeze)
echo   2  C            - Nov 17 setup: WhateverXe 0.8.2 + AMFIPass Mod (proven)
echo   3  A            - WhateverXe 0.8.3 + AMFIAnchor
echo   4  B            - WhateverXe 0.8.2 + AMFIAnchor
echo   5  N            - WhateverXe 0.8.3 display only, no GPU acceleration (test)
echo   0  cancel
echo.
choice /c 123450 /n /m "Type a number: "
if errorlevel 6 goto cancel
if errorlevel 5 goto pickN
if errorlevel 4 goto pickB
if errorlevel 3 goto pickA
if errorlevel 2 goto pickC
if errorlevel 1 goto pickM
:cancel
echo Cancelled. Nothing was changed.
pause
exit /b 0
:pickN
set "SRC=config-accel-noaccel.plist"
set "NAME=N (display only, no GPU acceleration)"
goto docopy
:pickB
set "SRC=config-accel-082.plist"
set "NAME=B (WhateverXe 0.8.2 + AMFIAnchor)"
goto docopy
:pickA
set "SRC=config-accel.plist"
set "NAME=A (WhateverXe 0.8.3 + AMFIAnchor)"
goto docopy
:pickC
set "SRC=config-accel-nov17.plist"
set "NAME=C (Nov 17 setup)"
goto docopy
:pickM
set "SRC=config-maintenance.plist"
set "NAME=MAINTENANCE"
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
