@echo off
rem G15 5520: check and repair the "1401" boot USB (FAT32) in Windows. Double-click it, then click Yes.
rem Run it after any forced power-off, before the next macOS start. Do not unplug the USB while it runs.
rem It only runs Windows' own CHKDSK on the USB labelled 1401, then shows which macOS mode is set.
setlocal
net session >nul 2>&1
if errorlevel 1 goto elevate
set "U="
for /f "usebackq delims=" %%d in (`powershell -NoProfile -Command "(Get-Volume -FileSystemLabel '1401' -ErrorAction SilentlyContinue | Select-Object -First 1).DriveLetter"`) do set "U=%%d"
if not defined U goto nousb
rem CHKDSK /X dismounts the USB, so never run from the USB itself: copy this file to TEMP and run that copy.
if /i "%~d0"=="%U%:" goto relaunch
for /f "usebackq delims=" %%t in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"`) do set "TS=%%t"
set "LOG=%USERPROFILE%\Documents\G15-USB-check-%TS%.txt"
echo.
echo  Checking and repairing the boot USB %U%: (about 1 minute). Do not unplug it.
echo.
echo Y| chkdsk %U%: /f /x > "%LOG%" 2>&1
set "RC=%errorlevel%"
type "%LOG%"
echo.
echo CHKDSK exit code %RC% (0 = no errors, 1 = errors fixed, 2 or 3 = could not finish)>> "%LOG%"
if "%RC%"=="0" echo RESULT: the USB is OK, nothing needed fixing.
if "%RC%"=="1" echo RESULT: errors were found and FIXED.
if "%RC%"=="2" echo STOP: CHKDSK could not finish - close other windows that use the USB and run this again.
if "%RC%"=="3" echo STOP: CHKDSK could not fix everything - tell Claude.
set "OC=%U%:\EFI\OC"
set "MODE=UNKNOWN - tell Claude"
call :is config-maintenance-safe.plist "MAINTENANCE in Safe Mode"
call :is config-maintenance.plist "MAINTENANCE normal"
call :is config-accel.plist "A"
call :is config-accel-dgpuoff.plist "D"
call :is config-accel-noccs.plist "TEST 7 (A + CCS off test build)"
call :is config-accel-dgpuoff-noccs.plist "TEST 8 (D + CCS off test build)"
call :is config-accel-noaccel.plist "N"
call :is config-accel-nov17.plist "C"
call :is config-accel-082.plist "B"
call :is config-maintenance-ctr.plist "old MAINTENANCE with the CPU topology kext ON"
echo Next macOS start uses: %MODE%
echo Next macOS start uses: %MODE%>> "%LOG%"
echo Log saved: %LOG%
pause
exit /b 0
:is
fc /b "%OC%\%~1" "%OC%\config.plist" >nul 2>&1
if not errorlevel 1 set "MODE=%~2"
exit /b 0
:relaunch
copy /Y "%~f0" "%TEMP%\G15-CHECK-USB.cmd" >nul
"%TEMP%\G15-CHECK-USB.cmd"
exit /b
:nousb
echo STOP: no USB with the label 1401 was found. Plug it in and run this again.
pause
exit /b 1
:elevate
echo Asking for administrator rights - click Yes in the next window.
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b
