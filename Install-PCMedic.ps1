#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
trap {
    $errorText = $_.Exception.ToString() + [Environment]::NewLine + $_.ScriptStackTrace
    $errorFile = Join-Path $env:TEMP 'PCMedic-Install-Error.txt'
    Set-Content -Path $errorFile -Value $errorText -Encoding UTF8
    [System.Windows.MessageBox]::Show("PC Medic could not be installed.`n`nThe error has been saved here:`n$errorFile`n`nThe log will open after you click OK.",'PC Medic installation error','OK','Error') | Out-Null
    Start-Process notepad.exe -ArgumentList ('"{0}"' -f $errorFile)
    break
}
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath))
    exit
}

$source = $PSScriptRoot
$target = Join-Path $env:ProgramFiles 'PC Medic'
New-Item -ItemType Directory -Path $target -Force | Out-Null
Copy-Item (Join-Path $source '*') $target -Recurse -Force

$shell = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath('Desktop')
$startMenu = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\PC Medic'
New-Item -ItemType Directory -Path $startMenu -Force | Out-Null

foreach ($shortcutPath in @((Join-Path $desktop 'PC Medic.lnk'), (Join-Path $startMenu 'PC Medic.lnk'))) {
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
    $shortcut.Arguments = '"' + (Join-Path $target 'PCMedic.vbs') + '"'
    $shortcut.WorkingDirectory = $target
    $shortcut.Description = 'Windows diagnostics and guided repair'
    $shortcut.Save()
}
$uninstallShortcut = $shell.CreateShortcut((Join-Path $startMenu 'Uninstall PC Medic.lnk'))
$uninstallShortcut.TargetPath = 'powershell.exe'
$uninstallShortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $target 'Uninstall-PCMedic.ps1') + '"'
$uninstallShortcut.WorkingDirectory = $target
$uninstallShortcut.Save()

[System.Windows.MessageBox]::Show('PC Medic is installed. A shortcut was added to your desktop and Start menu.','PC Medic','OK','Information') | Out-Null
Start-Process (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList ('"' + (Join-Path $target 'PCMedic.vbs') + '"')
