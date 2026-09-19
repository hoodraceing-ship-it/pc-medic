#Requires -Version 5.1
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath))
    exit
}
$target = Join-Path $env:ProgramFiles 'PC Medic'
$desktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) 'PC Medic.lnk'
$startMenu = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\PC Medic'
Remove-Item $desktopLink -Force -ErrorAction SilentlyContinue
Remove-Item $startMenu -Recurse -Force -ErrorAction SilentlyContinue
$cleanup = Join-Path $env:TEMP ('Remove-PCMedic-' + [guid]::NewGuid().ToString('N') + '.cmd')
Set-Content -Path $cleanup -Encoding ASCII -Value "@echo off`r`ntimeout /t 2 /nobreak >nul`r`nrmdir /s /q `"$target`"`r`ndel /q `"%~f0`""
Start-Process $cleanup -WindowStyle Hidden

