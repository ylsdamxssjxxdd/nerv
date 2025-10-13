@echo off
setlocal ENABLEDELAYEDEXPANSION
REM Windows build wrapper. Delegates to PowerShell script with same args.
set SCRIPT_DIR=%~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%build-win.ps1" %*
endlocal
