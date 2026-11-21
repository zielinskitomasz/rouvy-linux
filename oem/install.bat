@echo off
setlocal
set "SRC=\\host.lan\Data\setup\setup.ps1"
set "DST=C:\OEM\setup.ps1"
set tries=0
:retry
if exist "%SRC%" goto copy
set /a tries+=1
if %tries% GEQ 36 goto run
ping -n 6 127.0.0.1 >nul
goto retry
:copy
copy /Y "%SRC%" "%DST%" >nul
:run
if not exist "%DST%" goto missing
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DST%"
goto end
:missing
echo setup.ps1 not found on \\host.lan\Data\setup nor in C:\OEM
:end
endlocal
