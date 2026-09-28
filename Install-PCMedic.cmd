@echo off
setlocal
title PC Medic Installer
echo Starting PC Medic installer...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-PCMedic.ps1"
if errorlevel 1 (
  echo.
  echo PC Medic was not installed. Review the error shown above.
  pause
)
endlocal
